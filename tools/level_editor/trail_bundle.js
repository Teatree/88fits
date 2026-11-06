// Pass 130 (lane HOUSE): the Trail's bundle, in the page. Garry: "whenever we do show the level of trail, we also show
// the stats increases as just a bundle (a list of comma-separated increases) ... in one build, the trail is giving one
// set of stat increases and in the other build it's giving a different set. It's important to know which is which."
//
// One line that says what a Trail gives: "Attack damage +12%, Max health +30%, Reroll a run +2 · unlocks: 2 outlaws,
// 3 items, 1 stage"; "nothing yet" for a Trail that gives nothing. This file is the twin of game/core/systems/Trail.gd
// (bundle_text, tally, amount_text) and game/tools/trail_arg.gd (level_of, ids_upto), as tools/trail_bundle.py is:
// CHANGE ALL THREE. The fixture game/tests/fixtures/trail_bundle.json pins them together (pass130_HOUSE_test.gd reads
// it for the GDScript, selftest_HOUSE130.py for this file and the Python).
//
// Page-free (run under Node by the selftest); loaded by the Level Editor (the Sim tab) and analytics/dashboard.html:
//  - of(trail, types): a record's `trail` block as its bundle: the line the record carries (`bundle`, written by the
//    build that played the run), else the line worked out from its `upgrades` and `types` (a record from before pass 130)
//  - text(block, types): the line from a block's `upgrades` {type: summed value}, in the block's own order with the
//    words of its `types` {type: {name, kind, text}} when it carries them; a block without `types` reads by `types`
//    (a Trail file's `upgrades`), in that file's order. Then the block's `unlocks` {gift type: count} in short
//  - tally(data, ids): what the nodes `ids` of a Trail file give, added up: {upgrades, unlocks}
//  - levelOf(arg, levels), idsUpto(data, level, optional), forArg(data, arg, optional): the Trail a tool's trail=
//    argument names (none, quarter, half, full or a level) and its bundle, before any run has a record
'use strict';

const TrailBundle = (() => {
  const EMPTY = 'nothing yet';
  // [one, many, the gift types counted together], in the order they are written (Trail.UNLOCK_WORDS)
  const UNLOCK_WORDS = [['outlaw', 'outlaws', ['outlaw']], ['skin', 'skins', ['skin']], ['item', 'items', ['weapon', 'passive']],
    ['stage', 'stages', ['stage']], ['map', 'maps', ['map']], ['structure', 'structures', ['structure']],
    ['power-up', 'power-ups', ['powerup']], ['feature', 'features', ['feature']]];
  const GIFTS = ['upgrade', 'outlaw', 'skin', 'weapon', 'passive', 'stage', 'map', 'structure', 'powerup', 'feature'];
  const NAMED = { none: 0, quarter: 0.25, half: 0.5, full: 1 };
  const MINUS = '−';

  const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
  const isNum = (v) => typeof v === 'number' && isFinite(v);
  const num = (v, fallback) => (isNum(v) ? v : fallback);
  // Godot's round(): half away from zero
  const gdRound = (v) => (v < 0 ? -Math.floor(-v + 0.5) : Math.floor(v + 0.5));

  // Trail._plain: a whole number as it is, else one decimal when that says it, else two
  function plain(a) {
    if (Math.abs(a - gdRound(a)) < 0.001) return String(gdRound(a));
    if (Math.abs(a * 10 - gdRound(a * 10)) < 0.001) return a.toFixed(1);
    return a.toFixed(2);
  }

  // Trail.amount_text: "+3%", "+2.5%", "+2", "+0.3", "+2 s"; "" for a word
  function amountText(kind, value) {
    const sg = value >= 0 ? '+' : MINUS;
    const a = Math.abs(value);
    if (kind === 'percent') return sg + plain(a * 100) + '%';
    if (kind === 'count') return sg + String(gdRound(a));
    if (kind === 'seconds') return sg + plain(a) + ' s';
    if (kind === 'word') return '';
    return sg + plain(a);
  }

  // Trail.bundle_text
  function text(block, types) {
    const b = isObj(block) ? block : {};
    const ups = isObj(b.upgrades) ? b.upgrades : {};
    const own = isObj(b.types) ? b.types : null;
    const build = isObj(types) ? types : {};
    let order = [];
    if (own) order = Object.keys(ups);
    else {
      for (const t of Object.keys(build)) if (Object.prototype.hasOwnProperty.call(ups, t)) order.push(t);
      for (const t of Object.keys(ups)) if (order.indexOf(t) < 0) order.push(t);
    }
    const parts = [];
    for (const t of order) {
      const uv = own ? own[t] : build[t];
      const u = isObj(uv) ? uv : {};
      const kind = u.kind === undefined || u.kind === null ? 'flat' : String(u.kind);
      const name = u.name === undefined || u.name === null ? '' : String(u.name);
      const words = u.text === undefined || u.text === null ? '' : String(u.text);
      if (kind === 'word') { parts.push(name !== '' ? name : (words !== '' ? words : t)); continue; }
      const value = num(ups[t], 0);
      if (Math.abs(value) < 0.0000001) continue;
      parts.push((words !== '' ? words : (name !== '' ? name : t)) + ' ' + amountText(kind, value));
    }
    const got = [];
    if (isObj(b.unlocks)) {
      for (const w of UNLOCK_WORDS) {
        let n = 0;
        for (const g of w[2]) n += isNum(b.unlocks[g]) ? gdRound(b.unlocks[g]) : 0;
        if (n > 0) got.push(n + ' ' + (n === 1 ? w[0] : w[1]));
      }
    }
    let out = parts.join(', ');
    if (got.length) out += (out !== '' ? ' · ' : '') + 'unlocks: ' + got.join(', ');
    return out !== '' ? out : EMPTY;
  }

  // a record's block as its bundle: its own line when the build wrote one, else worked out ('' for no block at all)
  function of(trail, types) {
    if (!isObj(trail)) return '';
    if (typeof trail.bundle === 'string' && trail.bundle !== '') return trail.bundle;
    return text(trail, types);
  }

  // a Trail file's nodes as the rules read them (Trail._norm: an id once, kind node | choice | optional, level >= 1)
  function nodesOf(data) {
    const out = [];
    const seen = {};
    const raw = isObj(data) && Array.isArray(data.nodes) ? data.nodes : [];
    for (const e of raw) {
      if (!isObj(e)) continue;
      const id = e.id === undefined || e.id === null ? '' : String(e.id);
      if (id === '' || seen[id]) continue;
      seen[id] = true;
      const kind = e.kind === 'choice' || e.kind === 'optional' ? e.kind : 'node';
      out.push({ id, level: Math.max(isNum(e.level) ? gdRound(e.level) : 1, 1), kind,
        group: kind === 'choice' && e.group !== undefined && e.group !== null ? String(e.group) : '', gives: isObj(e.gives) ? e.gives : {} });
    }
    return out;
  }

  function levelsOf(data) {
    let top = 0;
    for (const n of nodesOf(data)) top = Math.max(top, n.level);
    return top;
  }

  const snap4 = (v) => Math.floor(v / 0.0001 + 0.5) * 0.0001;

  // Trail.tally
  function tally(data, ids) {
    const byId = {};
    for (const n of nodesOf(data)) byId[n.id] = n;
    const sums = {};
    const gifts = {};
    for (const raw of Array.isArray(ids) ? ids : []) {
      const n = byId[String(raw)];
      if (!n) continue;
      const type = n.gives.type === undefined || n.gives.type === null ? '' : String(n.gives.type);
      if (type === 'upgrade') {
        const ut = n.gives.upgrade === undefined || n.gives.upgrade === null ? '' : String(n.gives.upgrade);
        sums[ut] = (sums[ut] || 0) + num(n.gives.value, 0);
      } else if (type !== '') gifts[type] = (gifts[type] || 0) + 1;
    }
    const upgrades = {};
    const build = isObj(data) && isObj(data.upgrades) ? data.upgrades : {};
    for (const ut of Object.keys(build)) if (Object.prototype.hasOwnProperty.call(sums, ut)) upgrades[ut] = snap4(sums[ut]);
    for (const ut of Object.keys(sums)) if (!Object.prototype.hasOwnProperty.call(upgrades, ut)) upgrades[ut] = snap4(sums[ut]);
    const unlocks = {};
    for (const g of GIFTS) if (gifts[g]) unlocks[g] = gifts[g];
    return { upgrades, unlocks };
  }

  // trail_arg.gd level_of: a name's share of the levels (rounded half up), a number kept inside 0..levels; -1 else
  function levelOf(arg, levels) {
    const a = String(arg === undefined || arg === null ? '' : arg).trim().toLowerCase();
    if (a === '') return 0;
    if (Object.prototype.hasOwnProperty.call(NAMED, a)) return Math.floor(NAMED[a] * levels + 0.5);
    if (/^[+-]?\d+$/.test(a)) return Math.max(0, Math.min(levels, parseInt(a, 10)));
    return -1;
  }

  // trail_arg.gd ids_upto: every plain node of levels 1..level, one member of each choice group in turn (the k-th group
  // in file order its member k mod its size), the optional nodes only with `optional`
  function idsUpto(data, level, optional) {
    const nodes = nodesOf(data);
    const groups = {};
    const order = [];
    for (const n of nodes) {
      if (n.kind !== 'choice') continue;
      const key = n.level + '|' + n.group;
      if (!groups[key]) { groups[key] = []; order.push(key); }
      groups[key].push(n.id);
    }
    const pick = {};
    order.forEach((key, k) => { pick[groups[key][k % groups[key].length]] = true; });
    const out = [];
    for (const n of nodes) {
      if (n.level > level) continue;
      if (n.kind === 'node' || (n.kind === 'choice' && pick[n.id]) || (n.kind === 'optional' && optional)) out.push(n.id);
    }
    return out;
  }

  // the Trail a trail= argument names on the file `data`: {level, levels, ids, block, bundle}; null for an argument
  // that names nothing (and for "save": the PC save's own nodes are not the page's to know)
  function forArg(data, arg, optional) {
    const levels = levelsOf(data);
    const level = levelOf(arg, levels);
    if (level < 0) return null;
    const ids = idsUpto(data, level, !!optional);
    const block = tally(data, ids);
    return { level, levels, ids, block, bundle: text(block, isObj(data) ? data.upgrades : null) };
  }

  // the bundles of several runs (trail blocks) as a count by line, most runs first: [[bundle, runs], ...]; a list longer
  // than one row means the runs come from builds whose Trail gave different things
  function kinds(trails, types) {
    const count = {};
    const order = [];
    for (const t of trails || []) {
      const b = of(t, types);
      if (b === '') continue;
      if (count[b] === undefined) { count[b] = 0; order.push(b); }
      count[b] += 1;
    }
    return order.map((b) => [b, count[b]]).sort((x, y) => y[1] - x[1]);
  }

  return { EMPTY, UNLOCK_WORDS, GIFTS, NAMED, plain, amountText, text, of, nodesOf, levelsOf, tally, levelOf, idsUpto, forArg, kinds };
})();

if (typeof module !== 'undefined' && module.exports) module.exports = TrailBundle;
