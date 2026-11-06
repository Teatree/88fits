"""Pass 129, lane TRAIL-EDITOR: the Trail tab (docs/trail_schema.md).

Groups:
  model   trail_model.js under Node on fixtures/trail_sample.json (30 nodes: every kind, a 2-, 3- and 4-way choice, `any`,
          an optional beside its node, every `gives` type): the layout's numbers, `from` defaults, the rules at a
          previewed Trail Level (and with another member taken), prices, totals, the words
  draw    (sub-lane PREVIEW) what game/ui/TrailScreen.gd draws round the tiles: a crowded row's lifted smaller diamond,
          an optional node without `from` on its own level's nearest required node, rails as right-angled elbows, a
          choice group's mark "or" until one member is bought, then "lock"
  checks  every check fires on a broken copy of the sample, and the sample itself is clean
  csv     out and back equal; a spreadsheet's semicolons and decimal commas; a row without an id; read-only columns
          ignored; the summary of what an import changes
  edits   add / duplicate / delete / move a node, insert and remove a level (sections move with it), rename, ids not reused
  io      trail_io on a temporary content tree: the pick lists, a save in the file's layout (LF, one node a line, floats
          kept though the page sends 2 for 2.0), unchanged, a stale page (409), a bad shape (400), a missing file made
  page    the tab is on the page, app.js renders / saves / guards it, the hash routes know trail (and wanted; the Mirror tab is gone),
          server.py routes it, the scripts parse; the game's own trail.json has no error in the page's checks
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
FIXTURE = os.path.join(HERE, "fixtures", "trail_sample.json")

PICKS = {
    "outlaws": [{"id": "astro", "name": "Astro"}, {"id": "may", "name": "May"}],
    "skins": [{"id": "may:MAY-S", "name": "May, Carnival"}],
    "weapons": [{"id": "tommy_gun", "name": "Tommy Gun"}],
    "passives": [{"id": "adrenaline", "name": "Adrenaline", "mark": "item"}, {"id": "aegis", "name": "The Guardian", "mark": "card"}],
    "maps": [{"id": "red_canyon", "name": "Red Canyon", "stages": [{"id": "s1", "name": "Sundown"}, {"id": "dust", "name": "The Dust Bowl"}]}],
    "structures": [{"id": "totem_pole", "name": "Totem Pole"}], "powerups": [{"id": "rage", "name": "Rage"}],
    "features": ["wanted"], "currencies": ["gold"],
    "icons": ["might", "health", "tempo", "area", "luck", "crit_chance", "amount", "regen", "duration", "study", "stakes", "boss_stakes"],
    "stats": ["might", "max_hp", "cooldown", "area", "luck", "crit_chance", "amount", "regen", "duration", "xp_gain", "danger_hp",
              "danger_attack", "danger_speed", "danger_bounty", "boss_danger_hp", "boss_danger_attack"],
}

MODEL_JS = r"""
const M = require('./trail_model.js');
const fs = require('fs');
const P = JSON.parse(process.argv[3]);
const raw = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const d = M.normalise(raw);
const copy = () => JSON.parse(JSON.stringify(d));
const node = (x, id) => x.nodes.find((n) => n.id === id);
const codes = (x, picks) => M.check(x, picks === undefined ? P : picks).map((i) => `${i.sev}:${i.code}:${i.id || i.level || i.upgrade || ''}`);
const out = {};

// ---- model
const p = M.place(d), lay = M.layout(d), f = M.resolveFrom(d);
out.model = {
  same: JSON.stringify(M.normalise(raw)) === JSON.stringify(raw), filled: Object.keys(M.normalise({})).join(','),
  one: [p.n001.fx, p.n001.size], two: [p.n006.fx, p.n007.fx], three: [p.n012.fx, p.n013.fx, p.n014.fx], four: ['n019', 'n020', 'n021', 'n022'].map((i) => p[i].fx), fourSize: p.n019.size,
  beside: [p.n003.fx, p.n004.fx, p.n004.size], ownX: p.n017.fx, reqWithOwnX: p.n016.fx, top: [p.n028.fx, p.n029.fx, p.n030.fx, p.n028.size],
  sides: (() => { const g = { type: 'upgrade', upgrade: 'might', value: 0.01 }; const mk = (id, level, kind, x) => Object.assign({ id, level, kind, gives: g }, x == null ? {} : { x });
    const q = M.place({ nodes: [mk('a', 1, 'node', 0.7), mk('o1', 1, 'optional'), mk('o2', 1, 'optional'), mk('o3', 1, 'optional'), mk('b', 2, 'node'), mk('p1', 2, 'optional'), mk('c', 2, 'node'), mk('p2', 2, 'optional'), mk('p3', 2, 'optional'), mk('p4', 2, 'optional', 0.5),
      mk('q1', 3, 'optional'), mk('q2', 3, 'optional'), mk('r1', 4, 'node'), mk('r2', 4, 'node'), mk('r3', 4, 'node'), mk('r4', 4, 'node'), mk('r5', 4, 'optional')] });
    return ['a', 'o1', 'o2', 'o3', 'b', 'c', 'p1', 'p2', 'p3', 'p4', 'q1', 'q2', 'r1', 'r4', 'r5'].map((i) => q[i].fx).concat([q.q1.size, q.r1.size, q.r5.size, q.b.size]); })(),
  rows: [p.n001.y - p.n002.y, lay.rowY(1) - lay.rowY(2), lay.width, lay.levels], px: p.n001.x, endAbove: lay.rowY(lay.levels) - lay.endY,
  autoGroup: f.n008, own: f.n011.terms.map((t) => t.ids[0]).join(','), any: f.n015.need, first: f.n001.rails.length, optAuto: f.n017.rails.join(','),
  rails: [M.railIds(M.index(d), f, 'n008').join(','), M.railIds(M.index(d), f, 'n008', (x) => x === 'n007').join(','), M.railIds(M.index(d), f, 'n011').join(','), M.railIds(M.index(d), f, 'n016', (x) => x === 'n015').join(',')],
  dropped: (() => { const x = copy(); node(x, 'n010').from = ['n999', 'n010', 'n008', 'n008']; const g = M.resolveFrom(x).n010; return [g.ids.join(','), g.auto]; })(),
  sameName: (() => { const x = copy(); for (const id of ['n012', 'n013', 'n014']) node(x, id).group = 'c5'; const s = M.states(x, 9); return [s.state.n006, s.state.n007, s.state.n012, s.state.n013].join(','); })(),
  s0: M.states(d, 0).state.n001 + '/' + M.states(d, 0).state.n002, s3: ['n003', 'n004', 'n005', 'n006'].map((i) => M.states(d, 3).state[i]).join(','),
  s5: ['n006', 'n007', 'n008', 'n009'].map((i) => M.states(d, 5).state[i]).join(','), l5: M.states(d, 5).level,
  s10: ['n012', 'n013', 'n014', 'n015', 'n016', 'n017'].map((i) => M.states(d, 10).state[i]).join(','),
  picked: (() => { const s = M.states(d, 10, { [M.groupKey(node(d, 'n014'))]: 'n014' }); return [s.level, s.state.n012, s.state.n014, s.state.n015, s.state.n016, s.state.n017].join(','); })(),
  all: M.states(d, 99).level,
  ev: (() => { const e = M.evaluate(d, ['n001', 'n002']); return [e.level, e.state.n003, e.state.n004, e.state.n005].join(','); })(),
  evOpt: (() => { const e = M.evaluate(d, ['n001', 'n002', 'n003', 'n005']); return [e.level, e.state.n004, e.state.n006].join(','); })(),
  prices: [M.priceOf(d, node(d, 'n001')), M.priceOf(d, node(d, 'n005')), M.priceOf(d, node(d, 'n015')), M.priceOf(d, node(d, 'n024')), M.curvePrice(d.price, 10), M.curvePrice({ base: 5, k: 1, power: 1, round: 0 }, 3)],
  totals: (() => { const t = M.totals(d, 500); return [t.nodes, t.all, t.required, t.optional, t.with_optional, t.levels[4].required, t.levels[4].cumulative, t.runs, t.levels.length]; })(),
  up: M.upgradeTotals(d).filter((r) => ['might', 'tempo', 'stakes', 'motto'].includes(r.type)).map((r) => `${r.type}:${r.sure}/${r.optional}/${r.choice}/${r.max}:${r.line}`),
  stat: M.statTotals(d).filter((s) => ['cooldown', 'danger_speed'].includes(s.stat)).map((s) => `${s.stat} ${s.op} ${s.total}`),
  fmt: [M.fmtValue('percent', 0.03), M.fmtValue('percent', -0.125), M.fmtValue('count', 1), M.fmtValue('flat', 0.5), M.fmtValue('seconds', 2), M.fmtValue('word', 1)],
  parse: [M.parseValue('percent', '+3%'), M.parseValue('percent', '7'), M.parseValue('flat', '0,5'), M.parseValue('count', '+2'), M.parseValue('flat', 'x'), M.parseValue('flat', '') === undefined],
  give: ['n001', 'n005', 'n008', 'n009', 'n011', 'n016', 'n018', 'n023', 'n024', 'n025', 'n029'].map((i) => M.giveText(d, node(d, i), P)),
  colours: [M.coloursAt(d, 1).top.join(','), M.coloursAt(d, 6).top.join(','), M.coloursAt(d, 7).top.join(','), M.coloursAt(d, 3).motif, M.coloursAt(d, 13).motif],
};

// ---- what the game's screen draws round the tiles (sub-lane PREVIEW): the diamond, the rails, the choice marks
out.draw = (() => {
  const ix = M.index(d), r2 = (v) => Math.round(v * 100) / 100;
  const at = (level, pick) => { const s = M.states(d, level, pick); return { s, rails: (l) => M.rails(ix, s.from, lay, l, s.state), marks: (l) => M.choiceMarks(ix, lay, l, s.state) }; };
  const dm = (l) => { const k = M.diamondOf(ix, lay, l); return [k.lifted, k.d, k.px, r2(k.x), r2(lay.rowY(l) - k.y)]; };
  const pts = (r) => r.points.map((q) => [r2(q.x), r2(q.y - lay.rowY(lay.nodes[r.id].level))]);
  const run = (b) => [b.x, b.y, b.w, b.h].map(r2);
  const lk = (id, closed) => M.links(ix, f, lay, id, closed).map((k) => `${k.from}${k.thin ? ':thin' : ''}`).join(',');
  const a4 = at(4), a6 = at(6), a5 = at(5), a13 = at(13);
  const g = { type: 'upgrade', upgrade: 'might', value: 0.01 }, mk = (id, level, kind, x) => Object.assign({ id, level, kind, gives: g }, x || {});
  // a lone node; three required with an optional over the middle one; a level of optional nodes only; two required with
  // two optional (the second steps left of the leftmost); a node five levels up with its own `from`
  const y = { nodes: [mk('a', 1, 'node'), mk('b1', 2, 'node'), mk('b2', 2, 'node'), mk('b3', 2, 'node'), mk('bo', 2, 'optional', { x: 0.5 }), mk('co', 3, 'optional'),
    mk('d1', 4, 'node'), mk('d2', 4, 'node'), mk('do', 4, 'optional'), mk('dp', 4, 'optional'), mk('f', 7, 'node', { from: ['b1'], x: 0.6 })] };
  const yx = M.index(y), yl = M.layout(y, yx), yf = M.resolveFrom(y, yx);
  const ylk = (id) => M.links(yx, yf, yl, id).map((k) => `${k.from}${k.thin ? ':thin' : ''}`).join(',');
  const ydm = (l) => { const k = M.diamondOf(yx, yl, l); return [k.lifted, k.d, r2(yl.rowY(l) - k.y)]; };
  const far = M.rails(yx, yf, yl, 7, {})[0];
  const z = { nodes: [mk('z', 100, 'node'), mk('z1', 101, 'node'), mk('z2', 101, 'node'), mk('z3', 101, 'node'), mk('z4', 101, 'node')] }, zx = M.index(z), zl = M.layout(z, zx);
  return {
    diamonds: [dm(1), dm(9), dm(13), dm(18)], lone: [ydm(4), ydm(2), ydm(6), M.diamondOf(zx, zl, 100).px, M.diamondOf(zx, zl, 101).px],
    sizes: [M.DIAMOND, M.DIAMOND_SMALL, M.RAIL, M.RAIL_THIN],
    hang: [lk('n017'), lk('n030'), lk('n004'), lk('n008'), lk('n008', (x) => x === 'n007'), f.n017.rails.join(','), ylk('bo'), ylk('co'), ylk('do'), ylk('dp')],
    side: a4.rails(11).filter((r) => r.id === 'n017').map((r) => [r.from, r.width, r.points.length, pts(r)]),
    elbow: a4.rails(6).map((r) => [r.from, r.width, r.lit, r.shut, pts(r), r.runs.map(run).map((b) => [b[2], b[3]])]),
    straight: a4.rails(2).map((r) => [r.from, pts(r), run(r.runs[0]).slice(2)]),
    farElbow: [far.points.length, r2(far.points[1].y - yl.rowY(7)), r2(far.points[0].y - yl.rowY(7)), far.points[1].x === far.points[0].x && far.points[2].x === far.points[3].x && far.points[1].y === far.points[2].y],
    lit: [a6.rails(6).map((r) => `${r.from}:${r.lit}`).join(','), a5.rails(5).map((r) => `${r.id}:${r.lit}:${r.shut}`).join(',')],
    or: [a4.marks(5), a5.marks(5)].map((gs) => gs.map((k) => [k.group, k.taken, k.marks.map((m) => [m.kind, r2(m.x), r2(m.y - lay.rowY(5)), r2(m.w), m.h]), r2(k.bar.x0), r2(k.bar.x1)])),
    four: [at(12).marks(13), a13.marks(13)].map((gs) => gs.map((k) => k.marks.map((m) => `${m.kind}:${r2(m.x)}:${r2(m.w)}`).join(' '))),
    other: (() => { const s = at(9, { [M.groupKey(node(d, 'n014'))]: 'n014' }); return s.marks(9)[0].marks.map((m) => m.kind).join(','); })(),
    none: [a4.marks(1).length, M.choiceMarks(yx, yl, 2, {}).length, (() => { const x = copy(); x.nodes = x.nodes.filter((n) => n.id !== 'n007'); return M.choiceMarks(M.index(x), M.layout(x), 5, {}).length; })()],
  };
})();

// ---- checks
const broke = (fn, picks) => { const x = copy(); fn(x); return codes(x, picks); };
out.checks = {
  clean: codes(d), cleanNoPicks: codes(d, null),
  unknownOutlaw: broke((x) => { node(x, 'n005').gives.id = 'nobody'; }), unknownNoPicks: broke((x) => { node(x, 'n005').gives.id = 'nobody'; }, null),
  unknownUpgrade: broke((x) => { node(x, 'n001').gives.upgrade = 'nope'; }), unknownStage: broke((x) => { node(x, 'n011').gives.stage = 's9'; }),
  unknownFrom: broke((x) => { node(x, 'n010').from = ['n999']; }), unknownSkin: broke((x) => { node(x, 'n016').gives.id = 'may:NOPE'; }),
  duplicate: broke((x) => { node(x, 'n002').id = 'n001'; }),
  twice: broke((x) => { node(x, 'n018').gives = { type: 'outlaw', id: 'astro' }; }),
  onlyOptional: broke((x) => { node(x, 'n002').kind = 'optional'; }), emptyLevel: broke((x) => { x.nodes = x.nodes.filter((n) => n.id !== 'n002'); }),
  fromAbove: broke((x) => { node(x, 'n010').from = ['n011']; }), fromOwnRequired: broke((x) => { node(x, 'n010').from = ['n009']; }),
  optionalOwnLevel: codes(d).length,
  groupOne: broke((x) => { node(x, 'n007').kind = 'node'; delete node(x, 'n007').group; }),
  groupFive: broke((x) => { x.nodes.push({ id: 'n099', level: 13, kind: 'choice', group: 'c13', gives: { type: 'upgrade', upgrade: 'might', value: 0.01 } }); }),
  groupSpread: broke((x) => { node(x, 'n007').level = 6; }), groupTwice: broke((x) => { for (const id of ['n012', 'n013', 'n014']) node(x, id).group = 'c5'; }), noGroup: broke((x) => { delete node(x, 'n006').group; }),
  unlockInChoice: broke((x) => { node(x, 'n013').gives = { type: 'weapon', id: 'tommy_gun' }; node(x, 'n008').gives = { type: 'upgrade', upgrade: 'luck', value: 0.01 }; }),
  needsOptional: broke((x) => { node(x, 'n005').from = ['n004']; }),
  noIcon: broke((x) => { x.upgrades.might.icon = 'missing_picture'; }), noIconNoPicks: broke((x) => { x.upgrades.might.icon = 'missing_picture'; }, null),
  unreachable: broke((x) => { node(x, 'n015').need = 'all'; }),
  autoNeverShuts: broke((x) => { delete node(x, 'n016').from; delete node(x, 'n016').need; }),
  badX: broke((x) => { node(x, 'n017').x = 1.4; }), freeQuarter: broke((x) => { node(x, 'n017').x = 0.9; }),
  badKind: broke((x) => { node(x, 'n001').kind = 'bonus'; }), badLevel: broke((x) => { node(x, 'n001').level = 0; }),
  noValue: broke((x) => { delete node(x, 'n001').gives.value; }), wordNoValue: codes(d).filter((c) => c.includes('n029')).length,
  section: broke((x) => { x.sections[1].top = 'blue'; x.sections[2].from = 7; }), stat: broke((x) => { x.upgrades.might.effects[0].stat = 'mystery'; }),
  effect: broke((x) => { x.upgrades.might.effects[0].op = 'set'; }), currency: broke((x) => { x.currency = 'beans'; }),
  crowded: broke((x) => { for (const id of ['n0a', 'n0b', 'n0c', 'n0d']) x.nodes.push({ id, level: 1, kind: 'node', gives: { type: 'upgrade', upgrade: 'might', value: 0.01 } }); }),
  notObject: M.check(null).length, errorsOf: M.errorsOf(M.check((() => { const x = copy(); node(x, 'n002').id = 'n001'; return x; })(), P)).length,
};

// ---- csv
const csv = M.toCsv(d), back = M.fromCsv(csv, d);
const lines = csv.replace(/^﻿/, '').trim().split('\n');
const semi = csv.split('\n').map((l) => l.replace(/,(?=(?:[^"]*"[^"]*")*[^"]*$)/g, ';')).join('\n').replace(/;0\.03;/g, ';0,03;');
const edited = lines.slice();
edited[1] = edited[1].replace(/,40,40$/, ',99999,1');                         // the read-only columns scribbled on
edited[2] = edited[2].replace('health,0.05', 'health,6%');                    // a spreadsheet's percent
edited.splice(5, 1);                                                          // n005 gone
edited.push(',19,node,,,,upgrade,might,0.04,,,,New top,,,');                 // no id
const res = M.fromCsv(edited.join('\r\n') + '\r\n', d);
const diff = M.diffNodes(d.nodes, res.nodes);
out.csv = {
  bom: csv.charCodeAt(0) === 0xFEFF, head: lines[0], n: lines.length, first: lines[1], stage: lines[11], quoted: lines[30], cumulative: lines[30].endsWith(',' + M.totals(d).all),
  round: JSON.stringify(back.nodes) === JSON.stringify(d.nodes), problems: back.problems.length, keysKept: Object.keys(back.nodes[10]).join(','),
  semi: (() => { const r = M.fromCsv(semi, d); return [r.sep, r.nodes.length, r.nodes[0].gives.value, JSON.stringify(r.nodes) === JSON.stringify(d.nodes), r.problems.length].join('|'); })(),
  readOnly: JSON.stringify(res.nodes[0]) === JSON.stringify(d.nodes[0]), pct: res.nodes[1].gives.value,
  diff: [diff.added.join(','), diff.removed.join(','), diff.changed.map((c) => `${c.id}:${c.keys.join('+')}`).join(','), diff.same, res.new_ids.join(',')].join('|'),
  newNode: JSON.stringify(res.nodes[res.nodes.length - 1]),
  bad: M.fromCsv('id,level,kind\nn1,1,node\n', d).problems.length > 0, notNumber: M.fromCsv(lines[0] + '\nn001,one,node,,,,upgrade,might,0.03,,,,,,,\n', d).problems.join(' '),
  unknownCol: M.fromCsv(lines[0] + ',colour\n' + lines[1] + ',red\n', d).problems.join(' '),
  twice: M.fromCsv(lines[0] + '\n' + lines[1] + '\n' + lines[1] + '\n', d).problems.join(' '),
};

// ---- edits
const e = copy();
const used = new Set(['n040']);
const added = M.addNode(e, 5, node(e, 'n007'), used);
const dup = M.duplicateNode(e, 'n011', used);
const ins = copy(); const insId = M.insertLevel(ins, 7, null);
const rem = JSON.parse(JSON.stringify(ins)); M.removeLevel(rem, 7);
const del = copy(); M.deleteNodes(del, ['n009', 'n003']);
const mv = copy(); const moved = M.moveNode(mv, 'n030', -1); const stuck = M.moveNode(mv, 'n001', -1);
const ren = copy(); const okRen = M.renameId(ren, 'n009', 'gate'); const badRen = M.renameId(ren, 'n010', 'n001');
out.edits = {
  added, addedGives: JSON.stringify(node(e, added).gives), addedAt: e.nodes.findIndex((n) => n.id === added) - e.nodes.findIndex((n) => n.id === 'n007'),
  dup, dupAfter: e.nodes[e.nodes.findIndex((n) => n.id === 'n011') + 1].id, dupSame: JSON.stringify(Object.assign({}, node(e, dup), { id: 'n011' })) === JSON.stringify(node(e, 'n011')),
  next: M.nextId(d), nextUsed: M.nextId(d, new Set(['n250'])),
  insId, insLevels: [node(ins, 'n008').level, node(ins, 'n009').level, node(ins, insId).level, M.index(ins).max], insSections: ins.sections.map((s) => s.from).join(','),
  remBack: JSON.stringify(rem) === JSON.stringify(d),
  delFrom: [JSON.stringify(node(del, 'n011').from), 'from' in node(del, 'n004'), del.nodes.length],
  moved, stuck, movedLevel: node(mv, 'n030').level, sorted: mv.nodes.every((n, i) => i === 0 || mv.nodes[i - 1].level <= n.level),
  okRen, badRen, renFrom: node(ren, 'n011').from.join(','),
};
console.log(JSON.stringify(out));
"""


def _node(src, *args):
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False, encoding="utf-8", dir=HERE, prefix="_trail129_") as f:
        f.write(src)
    try:
        p = subprocess.run(["node", f.name] + list(args), capture_output=True, text=True, encoding="utf-8", cwd=HERE, timeout=120)
    finally:
        os.remove(f.name)
    if p.returncode != 0:
        raise RuntimeError(p.stderr[-1200:])
    return json.loads(p.stdout)


def _has(codes, want):
    return any(c.startswith(want) for c in codes)


def _model_checks(check, r):
    m = r["model"]
    check(m["same"] and m["filled"] == "version,currency,price,sections,upgrades,nodes,end", "TRAIL129 model: a whole file comes back as it is; an empty one gets every block")
    check(m["one"] == [0.5, 148] and m["two"] == [0.33, 0.6], "TRAIL129 layout: one node at 0.50, two at 0.33 and 0.60, tile 148 (%s %s)" % (m["one"], m["two"]))
    check(m["three"] == [0.2, 0.42, 0.64], "TRAIL129 layout: three required nodes sit at 0.20, 0.42, 0.64, left to right in file order (%s)" % m["three"])
    check(m["four"] == [0.12, 0.3, 0.48, 0.66] and m["fourSize"] == 132, "TRAIL129 layout: four sit at 0.12, 0.30, 0.48, 0.66 on 132 px tiles (%s)" % m["four"])
    check(m["beside"] == [0.5, 0.7, 116], "TRAIL129 layout: an optional node hangs 0.20 right of its node on a 116 px tile; the required node keeps the spine (%s)" % m["beside"])
    check(m["ownX"] == 0.7 and m["reqWithOwnX"] == 0.5, "TRAIL129 layout: an own x always wins; the required node is placed by the required count alone (%s, %s)" % (m["ownX"], m["reqWithOwnX"]))
    check(m["top"] == [0.33, 0.6, 0.8, 148], "TRAIL129 layout: two required and one optional: 0.33, 0.60, the optional at 0.80 (%s)" % m["top"])
    s = m["sides"]
    check(s[:4] == [0.7, 0.5, 0.9, 0.3], "TRAIL129 layout: the rightmost required node past 0.68: the first optional goes left, the second right, the third further left (%s)" % s[:4])
    check(s[4:10] == [0.33, 0.6, 0.8, 0.13, -0.07, 0.5], "TRAIL129 layout: the first optional right, the second left of the leftmost, more stepping out left; an optional's own x takes no side (%s)" % s[4:10])
    check(s[10:15] == [0.33, 0.6, 0.12, 0.66, 0.86] and s[15:] == [116, 132, 116, 148], "TRAIL129 layout: only optional nodes use the count table; tiles 116 optional, 132 with four required, else 148 (%s)" % s[10:])
    check(m["rows"] == [236, 236, 1080, 18] and m["px"] == 540 and m["endAbove"] == 236, "TRAIL129 layout: rows 236 apart, level 1 lowest, width 1080, the end plate one row above the last level (%s)" % m["rows"])
    g = m["autoGroup"]
    check(g["auto"] and g["terms"] == [] and g["ids"] == [] and g["rails"] == ["n006", "n007"] and g["need"] == "all",
          "TRAIL129 from: absent = no rule of its own (the level gate), its rails from the required nodes of the level below (%s)" % g)
    check(m["own"] == "n009,n010" and m["any"] == "any" and m["first"] == 0 and m["optAuto"] == "n015", "TRAIL129 from: an own list, need any, level 1 from nothing, an optional's default")
    check(m["rails"] == ["n006,n007", "n006", "n009,n010", "n014,n015"], "TRAIL129 from: rails as Trail.from_of draws them (a closed member left out; an own from as written) (%s)" % m["rails"])
    check(m["dropped"] == ["n008", False], "TRAIL129 from: an id that names no node, the node itself and a repeat are left out, as the game does (%s)" % m["dropped"])
    check(m["sameName"] == "bought,closed,bought,closed", "TRAIL129 rules: a group is its level and its name: the same name two levels up is another choice (%s)" % m["sameName"])
    check(m["s0"] == "open/locked" and m["s3"] == "bought,open,open,locked", "TRAIL129 rules: Trail Level 0 opens level 1 only; at 3 the optional beside n003 is open and level 4 is next (%s | %s)" % (m["s0"], m["s3"]))
    check(m["s5"] == "bought,closed,open,locked" and m["l5"] == 5, "TRAIL129 rules: a choice's first member taken closes its sibling and the level is done (%s)" % m["s5"])
    check(m["s10"] == "bought,closed,closed,bought,open,open", "TRAIL129 rules: at 10 the node with need any is bought through n012 (%s)" % m["s10"])
    check(m["picked"] == "10,closed,bought,closed,open,open", "TRAIL129 rules: with n014 taken, the node that needs n012 or n013 is closed for good and its level is done without it; what hangs on the level (no own from) stays open (%s)" % m["picked"])
    check(m["all"] == 18 and m["ev"] == "2,open,locked,locked" and m["evOpt"] == "4,open,open", "TRAIL129 rules: the whole Trail; evaluate on a bought set; an optional node on a done level stays open (%s | %s)" % (m["ev"], m["evOpt"]))
    check(m["prices"] == [40, 300, 570, 5000, 190, 8], "TRAIL129 prices: the curve rounded to 10, an own price, a multiplier, no rounding at round 0 (%s)" % m["prices"])
    t = m["totals"]
    check(t[0] == 30 and t[1] == 12290 and t[2] + t[3] == t[4] and t[5] == 80 and t[6] == 520 and abs(t[7] - t[2] / 500.0) < 1e-9 and t[8] == 18,
          "TRAIL129 totals: all nodes, required (a choice once) + optional, the running total, runs at coins a run (%s)" % t)
    up = dict(x.split(":", 1) for x in m["up"])
    check(up["might"].startswith("0.03/0/0.11/0.14:Attack damage +14% over 3 nodes") and up["stakes"].startswith("0/0.2/0/0.2:") and up["motto"].endswith("A word to ride by over 1 node"),
          "TRAIL129 totals: per upgrade type sure / optional / choices (the best member of each group) (%s)" % m["up"])
    check(m["stat"] == ["cooldown mul -0.11", "danger_speed add 0.08"], "TRAIL129 totals: per stat through the type's effects and per (%s)" % m["stat"])
    check(m["fmt"] == ["+3%", "-12.5%", "+1", "+0.5", "+2 s", ""], "TRAIL129 words: an amount as the player reads it (%s)" % m["fmt"])
    check(m["parse"] == [0.03, 0.07, 0.5, 2, None, True], "TRAIL129 words: what is typed back to the file's number (%s)" % m["parse"])
    check(m["give"] == ["Attack damage +3%", "Outlaw: Astro", "Weapon: Tommy Gun", "Item: Adrenaline", "Stage: The Dust Bowl", "Skin: May, Carnival", "Map: Red Canyon",
                        "Structure: Totem Pole", "Power-up: Rage", "Feature: Wanted", "A word to ride by"], "TRAIL129 words: what a node gives (%s)" % m["give"])
    c = m["colours"]
    check(c[0] == "247,178,74" and c[2] == "74,95,196" and c[1] not in (c[0], c[2]) and c[3] == "cactus" and c[4] == "dust", "TRAIL129 backdrop: a section's colours, blended on the levels before the next one (%s)" % c)


def _draw_checks(check, r):
    """Sub-lane PREVIEW: the four things game/ui/TrailScreen.gd draws round the tiles (docs/trail_schema.md "Layout")."""
    w = r["draw"]
    plain = [False, 44, 30, 64.8, 0]
    check(w["sizes"] == [44, 32, 22, 12], "TRAIL129 draw: the game's sizes: diamond 44, the small one 32, rail 22, thin 12 (%s)" % w["sizes"])
    check(w["diamonds"] == [plain, plain, [True, 32, 22, 64.8, 106], plain],
          "TRAIL129 draw: a row of four required nodes lifts its diamond: 32 px, its middle 32 + 8 above the 132 px tile's top (106 over the row), number 22 px; one, three and two-with-an-optional keep the 44 px diamond on the row at x 64.8 (%s)" % w["diamonds"])
    check(w["lone"] == [[True, 32, 98], [False, 44, 0], [False, 44, 0], 24, 17],
          "TRAIL129 draw: an optional node stepped left of the leftmost lifts the diamond too (over its 116 px tile: 98); three required and an empty level do not; a level from 100 writes 24 px (17 on the small one) (%s)" % w["lone"])
    h = w["hang"]
    check(h[:3] == ["n016:thin", "n029:thin", "n003:thin"] and h[5] == "n015",
          "TRAIL129 draw: an optional node without `from` hangs on its own level's nearest required node by a thin rail, not on the level below the rules name (%s, the rules: %s)" % (h[:3], h[5]))
    check(h[3:5] == ["n006,n007", "n006"], "TRAIL129 draw: a required node's rails stay Trail.from_of's, a closed member left out (%s)" % h[3:5])
    check(h[6:] == ["b2:thin", "b1:thin,b2:thin,b3:thin", "d2:thin", "d1:thin"],
          "TRAIL129 draw: the nearest by x (over the middle of three: the middle one; right of two: the right one; left: the left one); alone on its level it is drawn from the level below (%s)" % h[6:])
    check(w["side"] == [["n016", 12, 2, [[540, 0], [756, 0]]]], "TRAIL129 draw: that side rail is 12 px and straight along the row (%s)" % w["side"])
    check(w["elbow"] == [["n006", 22, False, False, [[356.4, 236], [356.4, 118], [540, 118], [540, 0]], [[22, 140], [205.6, 22], [22, 140]]],
                         ["n007", 22, False, False, [[648, 236], [648, 118], [540, 118], [540, 0]], [[22, 140], [130, 22], [22, 140]]]],
          "TRAIL129 draw: a rail between two nodes at different x has four points: up from the lower node, across at the middle of the gap (118 under the upper row), up into the node; each run a 22 px box squared off half a width past its ends (%s)" % w["elbow"])
    check(w["straight"] == [["n001", [[540, 236], [540, 0]], [22, 258]]], "TRAIL129 draw: two nodes in one column are joined straight: two points, one run (%s)" % w["straight"])
    check(w["farElbow"] == [4, 118, 1180, True], "TRAIL129 draw: from five levels down the cross-piece still sits half a row under the upper node, the runs right-angled (%s)" % w["farElbow"])
    check(w["lit"] == ["n006:true", "n006:true:false,n007:false:true"], "TRAIL129 draw: a rail is lit when both its ends are bought, shut when its node is closed (%s)" % w["lit"])
    check(w["or"] == [[["c5", False, [["or", 502.2, 0, 62, 36]], 356.4, 648]], [["c5", True, [["lock", 502.2, 0, 62, 36]], 356.4, 648]]],
          "TRAIL129 draw: a group's mark is \"or\" until one member is bought, then \"lock\": a 62 x 36 pill in the middle of the gap, on the bar from the first member to the last (%s)" % w["or"])
    check(w["four"] == [["or:226.8:44.4 or:421.2:44.4 or:615.6:44.4"], ["lock:226.8:44.4 lock:421.2:44.4 lock:615.6:44.4"]],
          "TRAIL129 draw: four members wear three marks, each as wide as the gap less 18 px (%s)" % w["four"])
    check(w["other"] == "lock,lock" and w["none"] == [0, 0, 0], "TRAIL129 draw: any member bought locks every mark of its group; no choice or a group of one has no mark (%s %s)" % (w["other"], w["none"]))


def _check_checks(check, r):
    c = r["checks"]
    check(c["clean"] == [] and c["cleanNoPicks"] == [], "TRAIL129 checks: the sample is clean (%s)" % c["clean"])
    check(_has(c["unknownOutlaw"], "error:unknown_id:n005") and not c["unknownNoPicks"], "TRAIL129 checks: an unknown outlaw (only with the pick lists)")
    check(_has(c["unknownUpgrade"], "error:unknown_id:n001") and _has(c["unknownStage"], "error:unknown_id:n011") and _has(c["unknownFrom"], "error:unknown_id:n010")
          and _has(c["unknownSkin"], "error:unknown_id:n016"), "TRAIL129 checks: an unknown upgrade type, stage, skin, from id")
    check(_has(c["duplicate"], "error:duplicate_id:n001"), "TRAIL129 checks: a duplicate id")
    check(_has(c["twice"], "error:given_twice:n018"), "TRAIL129 checks: a thing given by two nodes")
    check(_has(c["onlyOptional"], "error:no_required:2") and _has(c["emptyLevel"], "error:no_required:2"), "TRAIL129 checks: a level with no required node (only optional, or empty)")
    check(_has(c["fromAbove"], "error:from_level:n010") and _has(c["fromOwnRequired"], "error:from_level:n010") and c["optionalOwnLevel"] == 0,
          "TRAIL129 checks: a from naming a level not below; an optional node may name its own level")
    check(_has(c["groupOne"], "error:group_size:") and _has(c["groupFive"], "error:group_size:") and _has(c["noGroup"], "error:group:n006"),
          "TRAIL129 checks: a choice group of one, of five, a choice without a group")
    check(_has(c["groupSpread"], "warn:group_spread:") and len([x for x in c["groupSpread"] if x.startswith("error:group_size")]) == 2 and c["groupTwice"] == ["warn:group_spread:n012"],
          "TRAIL129 checks: a group spread over levels: each level's part is too small (errors), and the shared name is named (%s | %s)" % (c["groupSpread"], c["groupTwice"]))
    check(_has(c["unlockInChoice"], "warn:unlock_in_choice:n013") and not any(x.startswith("error") for x in c["unlockInChoice"]), "TRAIL129 checks: an unlock inside a choice is a warning (%s)" % c["unlockInChoice"])
    check(_has(c["needsOptional"], "warn:needs_optional:n005"), "TRAIL129 checks: a required node that depends on an optional one (warning)")
    check(c["noIcon"] == ["warn:no_icon:might"] and c["noIconNoPicks"] == [], "TRAIL129 checks: an upgrade type with no icon file (warning, with the icon list)")
    check(_has(c["unreachable"], "error:unreachable:n015"), "TRAIL129 checks: a node nobody can reach (it needs two members of one choice) (%s)" % c["unreachable"])
    check(c["autoNeverShuts"] == [], "TRAIL129 checks: a node without its own from is never closed by a choice below it (%s)" % c["autoNeverShuts"])
    check(_has(c["badX"], "error:x:n017") and c["freeQuarter"] == ["warn:x:n017"], "TRAIL129 checks: x outside 0..1; x in the free right quarter warns")
    check(_has(c["badKind"], "error:kind:n001") and _has(c["badLevel"], "error:level:n001") and _has(c["noValue"], "error:value:n001") and c["wordNoValue"] == 0,
          "TRAIL129 checks: a bad kind, level, a missing value (a word type needs none)")
    check(_has(c["section"], "error:sections:") and len([x for x in c["section"] if x.startswith("error:sections")]) == 2, "TRAIL129 checks: a section's colour and order (%s)" % c["section"])
    check(c["stat"] == ["warn:unknown_stat:might"] and _has(c["effect"], "error:upgrades:might") and _has(c["currency"], "error:unknown_id:"), "TRAIL129 checks: an unknown stat (warning), a bad effect, an unknown currency")
    check(c["crowded"] == ["warn:crowded:1"] and c["notObject"] == 1 and c["errorsOf"] >= 1, "TRAIL129 checks: more than four on a level warns; errorsOf picks the errors")


def _csv_checks(check, r):
    c = r["csv"]
    check(c["bom"] and c["head"] == "id,level,kind,group,from,need,gives_type,gives_what,value,price,price_mult,x,name,note,resolved_price,cumulative" and c["n"] == 31,
          "TRAIL129 csv: the header and one row per node (%s rows)" % (c["n"] - 1))
    check(c["first"] == "n001,1,node,,,,upgrade,might,0.03,,,,,,40,40" and c["stage"] == "n011,8,node,,n009 n010,all,stage,red_canyon/dust,,,,,The Dust Bowl opens,,140,1100",
          "TRAIL129 csv: a row as written (%s)" % c["stage"])
    check('"a designer\'s note, with a comma and ""quotes"""' in c["quoted"] and c["cumulative"], "TRAIL129 csv: a note with a comma and quotes is quoted; the last cumulative is the total")
    check(c["round"] and c["problems"] == 0 and c["keysKept"] == "id,level,kind,from,need,gives,name", "TRAIL129 csv: out and back equal, each node's own key order kept (%s)" % c["keysKept"])
    check(c["semi"] == ";|30|0.03|true|0", "TRAIL129 csv: a spreadsheet's semicolons and decimal commas read the same (%s)" % c["semi"])
    check(c["readOnly"] and c["pct"] == 0.06, "TRAIL129 csv: the read-only columns are ignored; 6% reads 0.06")
    check(c["diff"] == "n031|n005|n002:gives|28|n031", "TRAIL129 csv: what an import changes: added, removed, changed, the same, new ids (%s)" % c["diff"])
    check(json.loads(c["newNode"]) == {"id": "n031", "level": 19, "kind": "node", "gives": {"type": "upgrade", "upgrade": "might", "value": 0.04}, "name": "New top"},
          "TRAIL129 csv: a row without an id becomes a node in the schema's key order (%s)" % c["newNode"])
    check(c["bad"] and "not a number" in c["notNumber"] and "colour" in c["unknownCol"] and "earlier line" in c["twice"], "TRAIL129 csv: a header without its columns, a level that is no number, an unknown column, an id twice are named")


def _edit_checks(check, r):
    e = r["edits"]
    check(e["added"] == "n041" and json.loads(e["addedGives"])["upgrade"] == "tempo" and e["addedAt"] == 1, "TRAIL129 edits: a node added after its level's last, like it, with an id past every id seen (%s)" % e["added"])
    check(e["dup"] == "n042" and e["dupAfter"] == "n042" and e["dupSame"], "TRAIL129 edits: a duplicate beside its source, the same but for the id")
    check(e["next"] == "n031" and e["nextUsed"] == "n251", "TRAIL129 edits: the next id is one past the highest in use or ever seen")
    check(e["insLevels"] == [6, 8, 7, 19] and e["insSections"] == "1,8,14", "TRAIL129 edits: a level inserted: the levels from there and the sections above move up (%s, %s)" % (e["insLevels"], e["insSections"]))
    check(e["remBack"], "TRAIL129 edits: removing that level gives the file back exactly")
    check(e["delFrom"] == ['["n010"]', False, 28], "TRAIL129 edits: a deleted node leaves every from; an emptied from goes back to auto (%s)" % e["delFrom"])
    check(e["moved"] and not e["stuck"] and e["movedLevel"] == 17 and e["sorted"], "TRAIL129 edits: a node moved a level, never below 1, the file kept in level order")
    check(e["okRen"] and not e["badRen"] and e["renFrom"] == "gate,n010", "TRAIL129 edits: a rename follows into from; a taken id is refused")


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
        if isinstance(obj, str):
            f.write(obj)
        else:
            json.dump(obj, f)


def _as_page(x):
    """What the page sends back: JavaScript has one number type, so 2.0 comes home as 2."""
    if isinstance(x, float) and x == int(x):
        return int(x)
    if isinstance(x, dict):
        return {k: _as_page(v) for k, v in x.items()}
    if isinstance(x, list):
        return [_as_page(v) for v in x]
    return x


def _io_checks(check):
    import trail_io as T
    tmp = tempfile.mkdtemp(prefix="le129_")
    try:
        c = os.path.join(tmp, "content")
        src = open(FIXTURE, encoding="utf-8", newline="").read()
        _put(os.path.join(c, "trail", "trail.json"), src)
        _put(os.path.join(c, "characters", "astro", "astro.json"), {"id": "astro", "name": "Astro", "availability": "purchase", "price": 300})
        _put(os.path.join(c, "characters", "may", "may.json"), {"id": "may", "name": "May", "variants": {"MAY-G": {"note": "x"}, "MAY-S": {"skin": {"name": "Carnival"}}}})
        _put(os.path.join(c, "characters", "dad", "dad.json"), {"id": "dad", "name": "Dad", "availability": "hidden"})
        _put(os.path.join(c, "weapons", "tommy_gun", "tommy_gun.json"), {"id": "tommy_gun", "name": "Tommy Gun"})
        _put(os.path.join(c, "passives", "adrenaline", "adrenaline.json"), {"id": "adrenaline", "name": "Adrenaline"})
        _put(os.path.join(c, "passives", "energy_shield", "energy_shield.json"), {"id": "energy_shield", "name": "The Guardian", "line": True})
        _put(os.path.join(c, "passives", "aegis", "aegis.json"), {"id": "aegis", "name": "The Guardian Risen", "line": True, "evolves_from": "energy_shield"})
        _put(os.path.join(c, "maps", "red_canyon", "red_canyon.json"), {"id": "red_canyon", "name": "Red Canyon", "timeline_data": {"stage_list": [{"id": "s1", "name": "Sundown"}, {"id": "dust", "name": "The Dust Bowl"}]}})
        _put(os.path.join(c, "structures", "totem_pole", "totem_pole.json"), {"id": "totem_pole", "name": "Totem Pole"})
        _put(os.path.join(c, "pickups", "rage", "rage.json"), {"id": "rage", "name": "Rage"})
        _put(os.path.join(c, "currencies", "gold", "gold.json"), {"id": "gold", "name": "Gold"})
        _put(os.path.join(tmp, "art", "ui", "trail", "might.png"), "")
        _put(os.path.join(tmp, "art", "ui", "trail", "might.png.import"), "")
        _put(os.path.join(tmp, "art", "ui", "stages", "red_canyon_dust.jpg"), "")
        _put(os.path.join(tmp, "core", "systems", "StatSheet.gd"), 'const PLAYER_DEFAULTS := {\n\t"might": 1.0, "brand_new_stat": 0.0,\n}\n')
        srv = _Srv(tmp)
        d = T.read(srv)
        p = d["picks"]
        check(d["ok"] and d["exists"] and len(d["json"]["nodes"]) == 30 and d["file"] == "content/trail/trail.json" and d["mtime"], "TRAIL129 io: the file, its path and its mtime")
        check([o["id"] for o in p["outlaws"]] == ["astro", "dad", "may"] and p["outlaws"][1]["hidden"] and p["outlaws"][0]["icon"] == "/icon/hero/astro", "TRAIL129 io: the outlaws with their badges (%s)" % p["outlaws"])
        check(p["skins"] == [{"id": "may:MAY-S", "outlaw": "may", "code": "MAY-S", "hidden": False, "name": "May, Carnival", "icon": "/icon/hero/may/MAY-S"}], "TRAIL129 io: only the looks sold as skins (%s)" % p["skins"])
        check([(x["id"], x["mark"], x["evolved"]) for x in p["passives"]] == [("energy_shield", "card", False), ("adrenaline", "item", False), ("aegis", "card", True)],
              "TRAIL129 io: passives marked card or item, the evolutions last (%s)" % [(x["id"], x["mark"]) for x in p["passives"]])
        st = p["maps"][0]["stages"]
        check(p["maps"][0]["id"] == "red_canyon" and [s["id"] for s in st] == ["s1", "dust"] and st[0]["icon"] is None and st[1]["icon"] == "/api/wanted/art/stages/red_canyon_dust.jpg",
              "TRAIL129 io: the maps with their stage ids, names and pictures (%s)" % st)
        check([x["id"] for x in p["weapons"]] == ["tommy_gun"] and [x["id"] for x in p["structures"]] == ["totem_pole"] and [x["id"] for x in p["powerups"]] == ["rage"]
              and p["features"] == ["wanted"] and p["currencies"] == ["gold"] and p["icons"] == ["might"] and "cactus" in p["motifs"], "TRAIL129 io: weapons, structures, power-ups, features, currencies, the icon files present")
        check("brand_new_stat" in p["stats"] and "might" in p["stats"] and "max_hp" in p["stats"], "TRAIL129 io: the player stats (the editor's table and StatSheet.gd's own list)")
        check(T.icon_path(srv, "might") and T.icon_path(srv, "might.png") and T.icon_path(srv, "nope") is None and T.icon_path(srv, "../might") is None, "TRAIL129 io: the icon route serves only a plain name in art/ui/trail")
        path = T.path_of(srv)
        same = T.save(srv, _as_page(d["json"]), d["mtime"])
        check(same.get("ok") and same.get("unchanged") and not srv.backups and open(path, encoding="utf-8", newline="").read() == src, "TRAIL129 io: the file sent back as the page holds it changes nothing (%s)" % same)
        new = _as_page(json.loads(src))
        new["nodes"][0]["gives"]["value"] = 0.04
        new["nodes"][14]["price_mult"] = 4
        new["nodes"].append({"id": "n031", "level": 19, "kind": "node", "gives": {"type": "upgrade", "upgrade": "might", "value": 0.05}})
        res = T.save(srv, new, d["mtime"])
        after = open(path, encoding="utf-8", newline="").read()
        a, s = after.split("\n"), src.split("\n")
        diff = [ln for ln in a if ln not in set(s)]
        check(res.get("ok") and res.get("nodes") == 31 and srv.backups == ["trail"] and json.loads(after)["nodes"][0]["gives"]["value"] == 0.04, "TRAIL129 io: a save, with one backup (%s)" % res)
        check("\r" not in after and after.endswith("}\n") and len(a) == len(s) + 1 and len(diff) == 4, "TRAIL129 io: LF, one node a line: two changed nodes and one new one are four lines of diff (the two, the new one, the comma before it): %s" % len(diff))
        check('"power": 2.0' in after and '"value": 1.0}, "price_mult": 4.0' in after and '"per": -1.0' in after and '"value": 2.0' in after,
              "TRAIL129 io: the file's floats stay floats though the page sent whole numbers")
        check(list(json.loads(after).keys()) == list(json.loads(src).keys()) and list(json.loads(after)["nodes"][10].keys()) == ["id", "level", "kind", "from", "need", "gives", "name"], "TRAIL129 io: key order kept")
        check(T.dump(json.loads(after)) == after and T.dump(json.loads(src)) == src, "TRAIL129 io: the layout is stable (a dump of what was read is the file)")
        stale = T.save(srv, new, 1.0)
        check(stale.get("status") == 409 and stale.get("error") == "changed on disk", "TRAIL129 io: a stale page is refused (409)")
        bad = [T.save(srv, dict(new, nodes=[{"id": "a b", "level": 1, "kind": "node", "gives": {"type": "upgrade", "upgrade": "might"}}]), None),
               T.save(srv, dict(new, nodes=new["nodes"] + [dict(new["nodes"][0])]), None),
               T.save(srv, dict(new, nodes=[dict(new["nodes"][0], gives={"type": "upgrade", "upgrade": "nope", "value": 1})]), None),
               T.save(srv, dict(new, price={"base": 1}), None), T.save(srv, [], None)]
        check(all(b.get("status") == 400 for b in bad) and open(path, encoding="utf-8", newline="").read() == after, "TRAIL129 io: a bad id, a duplicate id, an unknown upgrade type, a broken price, a list are refused and nothing is written (%s)" % [b.get("error") for b in bad])
        os.remove(path)
        none = T.read(srv)
        made = T.save(srv, new, None)
        check(none["ok"] and none["exists"] is False and none["json"] is None and made.get("ok") and os.path.isfile(path) and made.get("backup") is None, "TRAIL129 io: no file reads as none; a save makes it")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _page_checks(check):
    idx = open(os.path.join(HERE, "index.html"), encoding="utf-8").read()
    app = open(os.path.join(HERE, "app.js"), encoding="utf-8").read()
    srv = open(os.path.join(HERE, "server.py"), encoding="utf-8").read()
    check('data-tab="trail"' in idx and 'id="tab-trail"' in idx and 'href="trail.css"' in idx and idx.index('src="trail_model.js"') < idx.index('src="trail.js"'),
          "TRAIL129 page: the Trail tab, its style and its two scripts (the model first) are on the page")
    check('data-tab="mirror"' not in idx and idx.index('data-tab="wanted"') < idx.index('data-tab="trail"') < idx.index('data-tab="instructions"'),
          "TRAIL129 page: the Mirror tab is gone (pass 129), the Trail tab in its place between Wanted and Instructions")
    check("Trail.render(panel)" in app and "Trail.save()" in app and "Trail.dirty()" in app and "Trail.key(e, typing)" in app, "TRAIL129 page: app.js renders, saves (Ctrl+S), guards and hands keys to the tab")
    check("import trail_io as TRAILIO" in srv and srv.count("TRAILIO.api_") == 2, "TRAIL129 page: server.py routes /api/trail (GET and POST)")
    r = _node("const J = require('./jobs_model.js'); console.log(JSON.stringify(['#trail', '#wanted', '#mirror', '#timeline', '#nope'].map((h) => J.parseHash(h))));")
    check(r == [{"tab": "trail"}, {"tab": "wanted"}, None, {"tab": "timeline"}, None], "TRAIL129 page: a reload comes back to the Trail and the Wanted tab; #mirror is no tab any more (%s)" % r)
    for f in ("trail.js", "trail_model.js", "app.js", "jobs_model.js"):
        p = subprocess.run(["node", "--check", os.path.join(HERE, f)], capture_output=True, text=True)
        check(p.returncode == 0, "TRAIL129 page: %s parses" % f)
    # the game's own file: the shape the game reads, and no error in the page's checks with the real pick lists
    import trail_io as T

    class Real:
        GAME = os.path.join(ROOT, "game")
        CONTENT = os.path.join(ROOT, "game", "content")
        rel = staticmethod(lambda p: os.path.relpath(p, ROOT).replace("\\", "/"))
        mtime_of = staticmethod(lambda p: round(os.path.getmtime(p), 3))
    real = T.path_of(Real)
    if not os.path.isfile(real):
        print("TRAIL129: game/content/trail/trail.json is not here: the game's file is not checked")
        return
    got = T.read(Real)
    check(got.get("ok") and T.check(got["json"]) == "", "TRAIL129 game: trail.json has the shape the game reads (%s)" % (got.get("error") or T.check(got.get("json"))))
    if got.get("ok"):
        issues = _node("const M = require('./trail_model.js'); const fs = require('fs'); const a = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));"
                       "console.log(JSON.stringify(M.errorsOf(M.check(M.normalise(a.json), a.picks)).map((x) => x.text)));", _dump_tmp(got))
        check(issues == [], "TRAIL129 game: trail.json has no error in the page's checks (%d nodes)%s" % (len(got["json"].get("nodes") or []), (": " + "; ".join(issues[:5])) if issues else ""))


_TMP = []


def _dump_tmp(obj):
    f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8")
    json.dump({"json": obj["json"], "picks": obj["picks"]}, f)
    f.close()
    _TMP.append(f.name)
    return f.name


def checks(check, run_node=None, server=None):
    if not shutil.which("node"):
        print("TRAIL129: node is not here: the Trail's model is not checked")
        return
    try:
        r = _node(MODEL_JS, FIXTURE, json.dumps(PICKS))
    except Exception as e:   # noqa: BLE001
        check(False, "TRAIL129 model: trail_model.js under Node: %s: %s" % (type(e).__name__, e))
        r = None
    groups = [(lambda c: _model_checks(c, r)), (lambda c: _draw_checks(c, r)), (lambda c: _check_checks(c, r)), (lambda c: _csv_checks(c, r)), (lambda c: _edit_checks(c, r))] if r else []
    for g in groups + [_io_checks, _page_checks]:
        try:
            g(check)
        except Exception as e:   # noqa: BLE001
            import traceback
            traceback.print_exc()
            check(False, "TRAIL129 %s: %s: %s" % (getattr(g, "__name__", "group"), type(e).__name__, e))
    for p in _TMP:
        try:
            os.remove(p)
        except OSError:
            pass
    del _TMP[:]


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
