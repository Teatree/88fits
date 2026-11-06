'use strict';
// Pass 129 (lane TRAIL-EDITOR): the Trail's page-free maths (docs/trail_schema.md), shared by the Trail tab (trail.js)
// and selftest_TRAIL129.py, which runs it under Node. Nothing here touches the page.
//
//   normalise(raw)            the file with its missing blocks filled in (a copy)
//   index(data)               {nodes, byId, byLevel, groups, max}: what every other function reads
//   resolveFrom(data)         {id: {terms, need, auto, ids, rails}}: a node's own `from` as the rules read it (ids that
//                             name no node are left out, as Trail.gd does); without one the node hangs on the level
//                             below: no rule of its own (the level gate asks for it), `rails` = where its rails come from
//   railIds(ix, from, id, isClosed)  Trail.from_of: the nodes a rail is drawn from (closed ones left out)
//   layout(data) / place(data)  the schema's "Layout": design width 1080, rows 236 apart, level 1 at the bottom;
//                             place -> {id: {x, y, size, fx, level}} in design pixels, y from the track's top
//   links / railPoints / railRun / rails / diamondOf / choiceMarks   what game/ui/TrailScreen.gd draws round the tiles
//                             (pass 129, sub-lane PREVIEW): the rails into a node (an optional node without `from` hangs
//                             on its own level's nearest required node), each rail as a right-angled elbow, the level's
//                             diamond (smaller and lifted on a crowded row), a choice group's bar and its OR / padlock
//   evaluate(data, bought)    the schema's rules 1-4 for a set of bought ids: {state: {id: bought|open|locked|closed}, level}
//   states(data, level, picks)  the same for a previewed Trail Level (every required node up to it bought, the first
//                             member of each choice unless `picks` {group: id} says another, optional nodes left open)
//   curvePrice / priceOf / totals / upgradeTotals / statTotals   resolved prices and what they add up to
//   fmtValue / parseValue / giveText   an amount the way the player reads it ("+3%"), and back
//   check(data, picks)        [{sev: error|warn, code, id?, level?, upgrade?, text}]; `picks` = GET /api/trail's lists
//                             (without them the ids of outlaws, items... are not checked)
//   toCsv / fromCsv / diffNodes   one row per node, and the same file back
//   addNode, duplicateNode, deleteNodes, moveNode, insertLevel, removeLevel, renameId, nextId   the editor's edits
//
// As a command: node trail_model.js <trail.json> [picks.json] prints the checks and exits 1 on an error.
const TrailModel = (() => {
  const W = 1080, ROW = 236, TILE = 148, TILE4 = 132, DIAMOND_X = 0.06, FREE_X = 0.75, RAIL = 22;
  const TOP_PAD = ROW * 1.5, BOTTOM_PAD = ROW * 0.75, OPTIONAL_TILE = 116, OPTIONAL_STEP = 0.20, OPTIONAL_RIGHT_MAX = 0.68;
  const AUTO_X = { 1: [0.5], 2: [0.33, 0.60], 3: [0.20, 0.42, 0.64], 4: [0.12, 0.30, 0.48, 0.66] };
  // game/ui/TrailScreen.gd's own numbers (RAIL_THIN, DIAMOND, DIAMOND_SMALL, its `+ 16.0` and `- 8.0`, _or_mark's box)
  const RAIL_THIN = 12, DIAMOND = 44, DIAMOND_SMALL = 32, DIAMOND_ROOM = 16, DIAMOND_LIFT = 8, OR_W = 62, OR_H = 36, OR_ROOM = 18;
  const KINDS = ['node', 'choice', 'optional'];
  const GIVES = ['upgrade', 'outlaw', 'skin', 'weapon', 'passive', 'stage', 'map', 'structure', 'powerup', 'feature'];
  const GIVE_WORDS = { upgrade: 'Upgrade', outlaw: 'Outlaw', skin: 'Skin', weapon: 'Weapon', passive: 'Card or item', stage: 'Stage', map: 'Map', structure: 'Structure', powerup: 'Power-up', feature: 'Feature' };
  const MOTIFS = ['cactus', 'star', 'skull', 'horseshoe', 'moon', 'flame', 'dust', 'none'];
  const VALUE_KINDS = ['percent', 'flat', 'count', 'seconds', 'word'];
  const NODE_KEYS = ['id', 'level', 'kind', 'group', 'from', 'need', 'gives', 'price', 'price_mult', 'x', 'name', 'note'];
  const CSV_COLS = ['id', 'level', 'kind', 'group', 'from', 'need', 'gives_type', 'gives_what', 'value', 'price', 'price_mult', 'x', 'name', 'note', 'resolved_price', 'cumulative'];
  const CSV_READ_ONLY = ['resolved_price', 'cumulative'];
  const DEFAULT_PRICE = { base: 40, k: 1.5, power: 2.0, round: 10 };

  const isObj = (x) => x != null && typeof x === 'object' && !Array.isArray(x);
  const isNum = (x) => typeof x === 'number' && Number.isFinite(x);
  const clone = (x) => (x === undefined ? undefined : JSON.parse(JSON.stringify(x)));
  const lvl = (n) => (isObj(n) && Number.isInteger(n.level) && n.level >= 1 ? n.level : 0);
  const required = (n) => n.kind !== 'optional';
  const tidy = (x) => Number(Number(x).toPrecision(12));   // 7 / 100 is 0.07, not 0.07000000000000001
  /** Trail.gd _group_key: a choice group is its level and its name (the same name on another level is another group). */
  const groupKey = (n) => `${lvl(n)}|${n.group}`;
  const inGroup = (n) => n.kind === 'choice' && n.group != null && n.group !== '';

  function normalise(raw) {
    const d = isObj(raw) ? clone(raw) : {};
    if (d.version == null) d.version = 1;
    if (typeof d.currency !== 'string' || !d.currency) d.currency = 'gold';
    if (!isObj(d.price)) d.price = clone(DEFAULT_PRICE);
    if (!Array.isArray(d.sections)) d.sections = [];
    if (!isObj(d.upgrades)) d.upgrades = {};
    if (!Array.isArray(d.nodes)) d.nodes = [];
    if (!isObj(d.end)) d.end = { text: 'To be continued' };
    return d;
  }

  function index(data) {
    const nodes = (isObj(data) && Array.isArray(data.nodes) ? data.nodes : []).filter(isObj);
    const byId = new Map(), byLevel = new Map(), groups = new Map();
    let max = 0;
    for (const n of nodes) {
      if (typeof n.id === 'string' && !byId.has(n.id)) byId.set(n.id, n);
      const l = lvl(n);
      if (!l) continue;
      if (!byLevel.has(l)) byLevel.set(l, []);
      byLevel.get(l).push(n);
      if (l > max) max = l;
      if (inGroup(n)) {
        const g = groupKey(n);
        if (!groups.has(g)) groups.set(g, []);
        groups.get(g).push(n);
      }
    }
    return { nodes, byId, byLevel, groups, max };
  }

  // ------------------------------------------------------------------ from

  /** What a node connects from, as Trail.gd reads it. An own `from` lists nodes one by one (an id that names no node,
   *  the node itself or a repeat is left out: a typo never closes a node for good). A node without one hangs on the
   *  level below it: no term of its own (the level gate already asks for that level), and its rails come from every
   *  required node of the nearest lower level that has one (`rails`). */
  function resolveFrom(data, ix0) {
    const ix = ix0 || index(data);
    const out = {};
    const below = new Map();
    const auto = (level) => {
      if (below.has(level)) return below.get(level);
      let ids = [];
      for (let l = level - 1; l >= 1 && !ids.length; l--) ids = (ix.byLevel.get(l) || []).filter(required).map((n) => n.id);
      below.set(level, ids);
      return ids;
    };
    for (const n of ix.nodes) {
      if (typeof n.id !== 'string') continue;
      const keep = [];
      for (const f of Array.isArray(n.from) ? n.from : []) if (typeof f === 'string' && ix.byId.has(f) && f !== n.id && !keep.includes(f)) keep.push(f);
      const own = keep.length > 0;
      out[n.id] = { terms: keep.map((id) => ({ ids: [id], group: null })), need: n.need === 'any' ? 'any' : 'all', auto: !own, ids: keep, rails: own ? keep : auto(lvl(n) || 1) };
    }
    return out;
  }
  /** Trail.from_of: the nodes a rail is drawn to `id` from: its own `from`, else every required node of the nearest
   *  lower level that has one still standing (`isClosed(id)` leaves the closed ones out: of a choice, the one taken). */
  function railIds(ix, from, id, isClosed) {
    const f = from[id], n = ix.byId.get(id);
    if (!f || !n) return [];
    if (!f.auto) return f.ids;
    for (let l = lvl(n) - 1; l >= 1; l--) {
      const ids = (ix.byLevel.get(l) || []).filter((m) => required(m) && !(isClosed && isClosed(m.id))).map((m) => m.id);
      if (ids.length) return ids;
    }
    return [];
  }

  // ------------------------------------------------------------------ layout

  /** The count table: the places across the screen (0..1) for `n` nodes, left to right (past four, spread evenly). */
  function autoSlots(n) {
    return AUTO_X[n] ? AUTO_X[n].slice() : Array.from({ length: n }, (_, i) => tidy(0.12 + (0.66 - 0.12) * (n > 1 ? i / (n - 1) : 0.5)));
  }

  function layout(data, ix0) {
    const ix = ix0 || index(data);
    const levels = Math.max(1, ix.max);
    const rowY = (l) => TOP_PAD + (levels - l) * ROW;
    const nodes = {};
    for (const [l, list] of ix.byLevel) {
      // the level's required nodes among themselves by their count, left to right in file order: the spine stays where
      // it is whether or not the level has optional nodes; an own x always wins
      const req = list.filter(required), opt = list.filter((x) => !required(x));
      const size = req.length >= 4 ? TILE4 : TILE;
      const fx = new Map();
      const xs = autoSlots(req.length);
      req.forEach((x, i) => fx.set(x, isNum(x.x) ? x.x : xs[i]));
      if (!req.length) {
        // only optional nodes: the count table
        const os = autoSlots(opt.length);
        opt.forEach((x, i) => fx.set(x, isNum(x.x) ? x.x : os[i]));
      } else {
        // optional nodes hang beside them: the first to the right of the rightmost required node (to the left of the
        // leftmost when that one is further right than 0.68), the second on the other side, the rest stepping out left
        const at = req.map((x) => fx.get(x));
        const right = Math.max(...at);
        let leftEdge = Math.min(...at), k = 0;
        const firstRight = right <= OPTIONAL_RIGHT_MAX;
        for (const x of opt) {
          if (isNum(x.x)) { fx.set(x, x.x); continue; }
          const goRight = k === 0 ? firstRight : k === 1 ? !firstRight : false;
          if (goRight) fx.set(x, tidy(right + OPTIONAL_STEP));
          else { leftEdge = tidy(leftEdge - OPTIONAL_STEP); fx.set(x, leftEdge); }
          k++;
        }
      }
      for (const x of list) {
        if (typeof x.id !== 'string' || nodes[x.id]) continue;
        const f = fx.get(x);
        nodes[x.id] = { x: Math.round(f * W * 100) / 100, y: rowY(l), size: required(x) ? size : OPTIONAL_TILE, fx: f, level: l };
      }
    }
    return { nodes, width: W, height: TOP_PAD + (levels - 1) * ROW + BOTTOM_PAD, levels, rowY, endY: TOP_PAD - ROW, diamondX: DIAMOND_X * W, row: ROW, rail: RAIL };
  }
  function place(data) { return layout(data).nodes; }

  // ---- what the game's screen draws round the tiles (game/ui/TrailScreen.gd: _links, _draw_canvas, _run, _or_mark)

  /** TrailScreen._links: the rails into node `id` -> [{from, thin}]. An optional node that names no `from` hangs on the
   *  nearest required node of its own level (by x; the first in file order when two are as near) by a thin rail. Every
   *  other node, and an optional one alone on its level, takes Trail.from_of (railIds); an optional node's rail is thin. */
  function links(ix, from, lay, id, isClosed) {
    const n = ix.byId.get(id), me = lay.nodes[id];
    if (!n || !me) return [];
    const thin = !required(n);
    if (thin && (!from[id] || from[id].auto)) {
      let best = null, bestD = Infinity;
      for (const m of ix.byLevel.get(lvl(n)) || []) {
        const q = lay.nodes[m.id];
        if (m === n || !required(m) || !q || ix.byId.get(m.id) !== m) continue;
        const dist = Math.abs(q.x - me.x);
        if (dist < bestD) { bestD = dist; best = m.id; }
      }
      if (best != null) return [{ from: best, thin: true }];
    }
    return railIds(ix, from, id, isClosed).map((f) => ({ from: f, thin }));
  }
  /** One rail's corners from the node it comes from (`a`) to the node it runs into (`b`), each {x, y}: two points when
   *  they share a row or a column, else a right-angled elbow of four: up from `a`, across at the middle of the gap
   *  under `b`'s row (b.y + ROW / 2), up into `b`. */
  function railPoints(a, b) {
    const A = { x: a.x, y: a.y }, B = { x: b.x, y: b.y };
    if (Math.abs(A.y - B.y) < 1 || Math.abs(A.x - B.x) < 1) return [A, B];
    const mid = B.y + ROW / 2;
    return [A, { x: A.x, y: mid }, { x: B.x, y: mid }, B];
  }
  /** TrailScreen._run: one straight run of a rail as a box `w` wide, its ends squared off half a width past them. */
  function railRun(p, q, w) {
    return { x: Math.min(p.x, q.x) - w / 2, y: Math.min(p.y, q.y) - w / 2, w: Math.abs(p.x - q.x) + w, h: Math.abs(p.y - q.y) + w };
  }
  /** The rails into level `level`'s nodes -> [{id, from, thin, width (22, thin 12), lit, shut, points, runs}]. `state`
   *  is {id: bought|open|locked|closed}: a rail is lit when both its ends are bought, shut when its node is closed. */
  function rails(ix, from, lay, level, state) {
    const s = state || {}, out = [];
    for (const n of ix.byLevel.get(level) || []) {
      const p = lay.nodes[n.id];
      if (!p || ix.byId.get(n.id) !== n) continue;
      for (const k of links(ix, from, lay, n.id, (x) => s[x] === 'closed')) {
        const q = lay.nodes[k.from];
        if (!q) continue;
        const width = k.thin ? RAIL_THIN : RAIL, points = railPoints(q, p);
        out.push({ id: n.id, from: k.from, thin: k.thin, width, lit: s[n.id] === 'bought' && s[k.from] === 'bought', shut: s[n.id] === 'closed',
          points, runs: points.slice(1).map((pt, i) => railRun(points[i], pt, width)) });
      }
    }
    return out;
  }
  /** The level's number diamond -> {x, y, d (half its diagonal), px (the number's size), lifted}. A row whose leftmost
   *  tile's left edge is left of 0.06 * 1080 + 44 + 16 wears the smaller one (32), lifted into the gap over the row: its
   *  middle 32 + 8 px above that tile's top edge. The number is 30 px (24 from level 100), scaled with the diamond. */
  function diamondOf(ix, lay, level) {
    let edge = W, side = TILE;
    for (const n of ix.byLevel.get(level) || []) {
      const p = lay.nodes[n.id];
      if (!p || ix.byId.get(n.id) !== n) continue;
      if (p.x - p.size / 2 < edge) { edge = p.x - p.size / 2; side = p.size; }
    }
    const x = DIAMOND_X * W, y = lay.rowY(level), lifted = edge < x + DIAMOND + DIAMOND_ROOM;
    const d = lifted ? DIAMOND_SMALL : DIAMOND;
    return { x, y: lifted ? y - side / 2 - DIAMOND_SMALL - DIAMOND_LIFT : y, d, px: Math.round((level < 100 ? 30 : 24) * d / DIAMOND), lifted };
  }
  /** Level `level`'s choice groups as the game marks them -> [{group, taken, bar: {x0, x1, y}, marks: [{kind, x, y, w, h}]}]:
   *  a bar through the members' middles, and between each pair (left to right) a mark in the middle of the gap between
   *  their tiles: "or" (OR on a gold pill) until one member is bought, then "lock" (a padlock on slate). The pill is
   *  36 px high and as wide as the gap less 18 px, 62 px at most. A group of one has no bar and no mark. */
  function choiceMarks(ix, lay, level, state) {
    const s = state || {}, groups = new Map();
    for (const n of ix.byLevel.get(level) || []) {
      const p = lay.nodes[n.id];
      if (!inGroup(n) || !p || ix.byId.get(n.id) !== n) continue;
      const key = String(n.group);
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push({ id: n.id, x: p.x, size: p.size });
    }
    const out = [], y = lay.rowY(level);
    for (const [group, mem] of groups) {
      if (mem.length < 2) continue;
      mem.sort((a, b) => a.x - b.x);
      const taken = mem.some((m) => s[m.id] === 'bought'), kind = taken ? 'lock' : 'or', marks = [];
      for (let i = 0; i + 1 < mem.length; i++) {
        const a = mem[i].x + mem[i].size / 2, b = mem[i + 1].x - mem[i + 1].size / 2;
        marks.push({ kind, x: (a + b) / 2, y, w: Math.min(b - a - OR_ROOM, OR_W), h: OR_H });
      }
      out.push({ group, taken, bar: { x0: mem[0].x, x1: mem[mem.length - 1].x, y }, marks });
    }
    return out;
  }

  /** The backdrop's colours at a level: a section's own, blending into the next one's over the three levels before it
   *  starts. -> {top, bottom} as [r, g, b]. */
  function hexRgb(h) { const m = /^#?([0-9a-f]{6})$/i.exec(String(h || '')); return m ? [0, 2, 4].map((i) => parseInt(m[1].slice(i, i + 2), 16)) : [40, 40, 40]; }
  function sectionsSorted(data) {
    return (isObj(data) && Array.isArray(data.sections) ? data.sections : []).filter((s) => isObj(s) && Number.isFinite(Number(s.from))).slice().sort((a, b) => a.from - b.from);
  }
  function sectionAt(data, level) {
    const list = sectionsSorted(data);
    let cur = null, next = null;
    for (let i = 0; i < list.length; i++) if (list[i].from <= level) { cur = list[i]; next = list[i + 1] || null; }
    if (!cur) cur = list[0] || null;
    return { cur, next };
  }
  function coloursAt(data, level) {
    const { cur, next } = sectionAt(data, level);
    if (!cur) return { top: [34, 34, 33], bottom: [26, 26, 25], motif: 'none' };
    let top = hexRgb(cur.top), bottom = hexRgb(cur.bottom);
    if (next && cur.from <= level && level >= next.from - 3 && level < next.from) {
      const t = (level - (next.from - 3) + 1) / 4;   // a quarter, a half, three quarters on the three levels before
      const mix = (a, b) => a.map((v, i) => Math.round(v + (b[i] - v) * t));
      top = mix(top, hexRgb(next.top)); bottom = mix(bottom, hexRgb(next.bottom));
    }
    return { top, bottom, motif: cur.motif || 'none' };
  }

  // ------------------------------------------------------------------ the rules

  /** Who connects from whom: {id: [the ids of the nodes that list it]}. */
  function dependents(ix, from) {
    const deps = new Map();
    for (const n of ix.nodes) {
      const f = from[n.id];
      if (!f) continue;
      for (const id of f.ids) { if (!deps.has(id)) deps.set(id, []); deps.get(id).push(n.id); }
    }
    return deps;
  }
  /** `seeds` closed for good, and with them every node whose `from` can then no longer be met (rule 1), added to
   *  `closed`. A bought node never closes. The cost follows what closes, not the size of the Trail. */
  function spread(ix, from, deps, closed, seeds, bought) {
    const queue = [];
    for (const id of seeds) if (!closed.has(id) && !(bought && bought.has(id))) { closed.add(id); queue.push(id); }
    const dead = (t) => t.ids.every((x) => closed.has(x) || !ix.byId.has(x));
    while (queue.length) {
      for (const dep of deps.get(queue.pop()) || []) {
        if (closed.has(dep) || (bought && bought.has(dep))) continue;
        const f = from[dep];
        if (f.need === 'any' ? f.terms.every(dead) : f.terms.some(dead)) { closed.add(dep); queue.push(dep); }
      }
    }
    return closed;
  }

  function evaluate(data, bought0, ix0, from0, deps0) {
    const ix = ix0 || index(data);
    const from = from0 || resolveFrom(data, ix);
    const bought = bought0 instanceof Set ? bought0 : new Set(bought0 || []);
    // rule 1: the siblings of a bought choice, and whatever names those in its own `from`
    const seeds = [];
    for (const n of ix.nodes) {
      if (typeof n.id !== 'string' || bought.has(n.id) || !inGroup(n)) continue;
      if ((ix.groups.get(groupKey(n)) || []).some((m) => m !== n && bought.has(m.id))) seeds.push(n.id);
    }
    const closed = spread(ix, from, deps0 || dependents(ix, from), new Set(), seeds, bought);
    const done = (l) => (ix.byLevel.get(l) || []).every((n) => !required(n) || closed.has(n.id) || bought.has(n.id));
    let level = 0;
    while (level < ix.max && done(level + 1)) level++;
    const met = (id) => {
      const f = from[id];
      if (!f || !f.terms.length) return true;
      const ok = (t) => t.ids.some((x) => bought.has(x));
      return f.need === 'any' ? f.terms.some(ok) : f.terms.every(ok);
    };
    const state = {};
    for (const n of ix.nodes) {
      if (typeof n.id !== 'string' || state[n.id]) continue;
      state[n.id] = bought.has(n.id) ? 'bought' : closed.has(n.id) ? 'closed' : (lvl(n) <= level + 1 && met(n.id)) ? 'open' : 'locked';
    }
    return { state, level, closed };
  }

  function states(data, level, picks) {
    const ix = index(data);
    const from = resolveFrom(data, ix);
    const want = Math.max(0, Math.min(ix.max, Math.round(Number(level) || 0)));
    const bought = new Set();
    const pick = isObj(picks) ? picks : {};
    const deps = dependents(ix, from);
    const closed = evaluate(data, bought, ix, from, deps).closed;
    for (let l = 1; l <= want; l++) {
      const seen = new Set();
      for (const n of ix.byLevel.get(l) || []) {
        if (!required(n) || closed.has(n.id)) continue;
        if (inGroup(n)) {
          const g = groupKey(n);
          if (seen.has(g)) continue;
          seen.add(g);
          const members = (ix.groups.get(g) || []).filter((m) => !closed.has(m.id));
          const chosen = members.find((m) => m.id === pick[g]) || members[0];
          if (chosen) { bought.add(chosen.id); spread(ix, from, deps, closed, (ix.groups.get(g) || []).filter((m) => m !== chosen).map((m) => m.id), bought); }
        } else bought.add(n.id);
      }
      // an optional node a bought one cannot do without is bought too
      for (const id of Array.from(bought)) {
        const f = from[id];
        if (!f || f.auto) continue;
        const opt = f.terms.map((t) => ix.byId.get(t.ids[0])).filter((m) => m && !required(m));
        if (f.need === 'all') for (const m of opt) bought.add(m.id);
        else if (opt.length && !f.terms.some((t) => bought.has(t.ids[0]))) bought.add(opt[0].id);
      }
    }
    const res = evaluate(data, bought, ix, from, deps);
    return { state: res.state, level: res.level, want, bought: Array.from(bought), from };
  }

  // ------------------------------------------------------------------ prices

  function curvePrice(price, level) {
    const p = isObj(price) ? price : {};
    const raw = (isNum(p.base) ? p.base : 0) + (isNum(p.k) ? p.k : 0) * Math.pow(level, isNum(p.power) ? p.power : 1);
    const r = isNum(p.round) ? p.round : 0;
    return r > 0 ? Math.round(raw / r) * r : Math.round(raw);
  }
  function priceOf(data, n) {
    if (isNum(n.price)) return Math.trunc(n.price);
    return Math.max(0, Math.round(curvePrice(data.price, lvl(n) || 1) * (isNum(n.price_mult) ? n.price_mult : 1)));
  }

  /** What the Trail costs. A choice counts once at its dearest member; `perRun` coins a run gives the runs. */
  function totals(data, perRun) {
    const ix = index(data);
    const per = isNum(perRun) && perRun > 0 ? perRun : 0;
    const levels = [];
    let cum = 0, cumAll = 0, all = 0, optional = 0, count = 0;
    for (let l = 1; l <= ix.max; l++) {
      const list = ix.byLevel.get(l) || [];
      let req = 0, opt = 0;
      const groupMax = new Map();
      for (const n of list) {
        const p = priceOf(data, n);
        all += p; count++;
        if (!required(n)) opt += p;
        else if (inGroup(n)) groupMax.set(groupKey(n), Math.max(groupMax.get(groupKey(n)) || 0, p));
        else req += p;
      }
      for (const v of groupMax.values()) req += v;
      cum += req; cumAll += req + opt; optional += opt;
      levels.push({ level: l, nodes: list.length, required: req, optional: opt, cumulative: cum, cumulative_all: cumAll, runs: per ? cum / per : null });
    }
    return { nodes: count, levels, all, required: cum, optional, with_optional: cumAll, runs: per ? cum / per : null, runs_with_optional: per ? cumAll / per : null };
  }

  /** Per upgrade type: how many nodes give it and how much: `sure` (plain nodes), `optional`, `choice` (the most its
   *  choice groups can give: one member each), `max` = all three. */
  function upgradeTotals(data) {
    const ix = index(data);
    const ups = isObj(data.upgrades) ? data.upgrades : {};
    const out = {};
    const rec = (t) => out[t] || (out[t] = { type: t, name: (ups[t] && ups[t].name) || t, kind: (ups[t] && ups[t].kind) || 'flat', words: (ups[t] && ups[t].text) || t, count: 0, sure: 0, optional: 0, choice: 0, max: 0 });
    for (const t of Object.keys(ups)) rec(t);
    const best = new Map();
    for (const n of ix.nodes) {
      const g = n.gives;
      if (!isObj(g) || g.type !== 'upgrade' || typeof g.upgrade !== 'string') continue;
      const r = rec(g.upgrade);
      const v = isNum(g.value) ? g.value : 0;
      r.count++;
      if (!required(n)) r.optional = tidy(r.optional + v);
      else if (inGroup(n)) { const key = g.upgrade + '\n' + groupKey(n); best.set(key, Math.max(best.get(key) || 0, v)); }
      else r.sure = tidy(r.sure + v);
    }
    for (const [key, v] of best) { const r = out[key.split('\n')[0]]; r.choice = tidy(r.choice + v); }
    return Object.values(out).map((r) => {
      r.max = tidy(r.sure + r.optional + r.choice);
      r.line = r.count ? `${r.words} ${fmtValue(r.kind, r.max)} over ${r.count} node${r.count === 1 ? '' : 's'}`.replace(/\s+/g, ' ') : `${r.words}: no node yet`;
      return r;
    });
  }

  /** Per stat and op: what every bought node of the Trail would add up to (the types' effects times their totals). */
  function statTotals(data) {
    const ups = isObj(data.upgrades) ? data.upgrades : {};
    const out = new Map();
    for (const r of upgradeTotals(data)) {
      const u = ups[r.type];
      if (!u || !Array.isArray(u.effects) || !r.count) continue;
      for (const e of u.effects) {
        if (!isObj(e) || typeof e.stat !== 'string') continue;
        const key = e.stat + ' ' + (e.op || 'add');
        const cur = out.get(key) || { stat: e.stat, op: e.op || 'add', total: 0, sure: 0, types: [] };
        const per = isNum(e.per) ? e.per : 1;
        cur.total = tidy(cur.total + r.max * per); cur.sure = tidy(cur.sure + r.sure * per);
        if (!cur.types.includes(r.type)) cur.types.push(r.type);
        out.set(key, cur);
      }
    }
    return Array.from(out.values());
  }

  // ------------------------------------------------------------------ words

  function trimNum(x, digits) { return String(Number(Number(x).toFixed(digits == null ? 4 : digits))); }
  function fmtValue(kind, value) {
    if (kind === 'word') return '';
    if (!isNum(value)) return '';
    const s = value < 0 ? '-' : '+';
    const a = Math.abs(value);
    if (kind === 'percent') return `${s}${trimNum(a * 100, 2)}%`;
    if (kind === 'seconds') return `${s}${trimNum(a, 2)} s`;
    return `${s}${trimNum(a, 3)}`;
  }
  /** What is typed in a value cell -> the number the file holds (a percent type takes percent points: "3", "+3%" and
   *  "3 %" are all 0.03), null when it is no number, undefined for an empty cell. */
  function parseValue(kind, text) {
    let s = String(text == null ? '' : text).trim().replace(/\s+/g, '').replace(',', '.');
    if (s === '') return undefined;
    const pct = /%$/.test(s);
    s = s.replace(/%$/, '').replace(/s$/i, '').replace(/^\+/, '');
    if (!/^-?(\d+\.?\d*|\.\d+)$/.test(s)) return null;
    const v = Number(s);
    return kind === 'percent' || pct ? tidy(v / 100) : v;
  }

  function nameIn(list, id) {
    const hit = (Array.isArray(list) ? list : []).find((x) => isObj(x) && x.id === id);
    return hit && hit.name ? hit.name : id;
  }
  function giveWhat(g) {
    if (!isObj(g)) return '';
    if (g.type === 'upgrade') return g.upgrade == null ? '' : String(g.upgrade);
    if (g.type === 'stage') return `${g.map == null ? '' : g.map}/${g.stage == null ? '' : g.stage}`;
    return g.id == null ? '' : String(g.id);
  }
  /** Trail.give_text: "Attack damage +3%", "Outlaw: Astro". */
  function giveText(data, n, picks) {
    const g = isObj(n) ? n.gives : null;
    if (!isObj(g)) return '';
    const p = isObj(picks) ? picks : {};
    if (g.type === 'upgrade') {
      const u = isObj(data.upgrades) ? data.upgrades[g.upgrade] : null;
      if (!u) return `${g.upgrade || '?'} ${isNum(g.value) ? g.value : ''}`.trim();
      return `${u.text || u.name || g.upgrade} ${fmtValue(u.kind, g.value)}`.trim();
    }
    if (g.type === 'outlaw') return `Outlaw: ${nameIn(p.outlaws, g.id)}`;
    if (g.type === 'skin') return `Skin: ${nameIn(p.skins, g.id)}`;
    if (g.type === 'weapon') return `Weapon: ${nameIn(p.weapons, g.id)}`;
    if (g.type === 'passive') { const hit = (p.passives || []).find((x) => x.id === g.id); return `${hit && hit.mark === 'card' ? 'Card' : hit ? 'Item' : 'Card or item'}: ${hit ? hit.name : g.id}`; }
    if (g.type === 'stage') { const m = (p.maps || []).find((x) => x.id === g.map); const st = m && (m.stages || []).find((x) => x.id === g.stage); return `Stage: ${st ? st.name : g.stage}`; }
    if (g.type === 'map') return `Map: ${nameIn(p.maps, g.id)}`;
    if (g.type === 'structure') return `Structure: ${nameIn(p.structures, g.id)}`;
    if (g.type === 'powerup') return `Power-up: ${nameIn(p.powerups, g.id)}`;
    if (g.type === 'feature') return `Feature: ${String(g.id || '').replace(/^./, (c) => c.toUpperCase())}`;
    return String(g.type || '');
  }

  // ------------------------------------------------------------------ checks

  function check(data, picks) {
    const out = [];
    const add = (sev, code, where, text) => out.push(Object.assign({ sev, code, text }, where || {}));
    const err = (code, where, text) => add('error', code, where, text);
    const warn = (code, where, text) => add('warn', code, where, text);
    if (!isObj(data)) { err('file', null, 'The file is not a JSON object'); return out; }
    const P = isObj(picks) ? picks : null;
    const ids = (k) => (P && Array.isArray(P[k]) ? new Set(P[k].map((x) => (isObj(x) ? x.id : x))) : null);

    // the blocks
    const pr = data.price;
    if (!isObj(pr)) err('price', null, 'price must be {base, k, power, round}');
    else for (const k of ['base', 'k', 'power', 'round']) if (!isNum(pr[k]) || pr[k] < 0) err('price', null, `price.${k} must be a number, 0 or more`);
    const cur = ids('currencies');
    if (typeof data.currency !== 'string' || !data.currency) err('currency', null, 'currency must name a currency (gold)');
    else if (cur && !cur.has(data.currency)) err('unknown_id', null, `Currency "${data.currency}" is not in content/currencies`);

    const secs = Array.isArray(data.sections) ? data.sections : [];
    if (!Array.isArray(data.sections)) err('sections', null, 'sections must be a list');
    let last = 0;
    secs.forEach((s, i) => {
      const at = { section: i };
      if (!isObj(s)) { err('sections', at, `Section ${i + 1} is not an object`); return; }
      if (!Number.isInteger(s.from) || s.from < 1) err('sections', at, `Section ${i + 1} ("${s.name || ''}"): from must be a level, 1 or more`);
      else { if (s.from <= last) err('sections', at, `Section ${i + 1} ("${s.name || ''}") starts at level ${s.from}, not above the one before it (${last})`); last = s.from; }
      for (const k of ['top', 'bottom']) if (!/^[0-9a-f]{6}$/i.test(String(s[k] || ''))) err('sections', at, `Section ${i + 1} ("${s.name || ''}"): ${k} must be a colour as six hex digits without #`);
      if (s.motif != null && !MOTIFS.includes(s.motif)) warn('sections', at, `Section ${i + 1} ("${s.name || ''}"): motif "${s.motif}" is not one of ${MOTIFS.join(', ')}`);
    });
    if (secs.length && isObj(secs[0]) && secs[0].from !== 1) warn('sections', { section: 0 }, 'The first section should start at level 1 (the levels below it take its colours)');

    const ups = isObj(data.upgrades) ? data.upgrades : {};
    if (!isObj(data.upgrades)) err('upgrades', null, 'upgrades must be an object, one entry per upgrade type');
    const icons = P && Array.isArray(P.icons) ? new Set(P.icons) : null;
    const stats = P && Array.isArray(P.stats) ? new Set(P.stats) : null;
    for (const [t, u] of Object.entries(ups)) {
      const at = { upgrade: t };
      if (!isObj(u)) { err('upgrades', at, `Upgrade type ${t} is not an object`); continue; }
      if (!VALUE_KINDS.includes(u.kind)) err('upgrades', at, `Upgrade type ${t}: kind must be one of ${VALUE_KINDS.join(', ')}`);
      if (!Array.isArray(u.effects) || !u.effects.length) warn('upgrades', at, `Upgrade type ${t} has no effect: buying it changes nothing`);
      for (const e of Array.isArray(u.effects) ? u.effects : []) {
        if (!isObj(e) || typeof e.stat !== 'string' || !e.stat || !['add', 'mul'].includes(e.op) || !isNum(e.per)) { err('upgrades', at, `Upgrade type ${t}: every effect needs stat, op (add or mul) and a number per`); continue; }
        if (stats && !stats.has(e.stat)) warn('unknown_stat', at, `Upgrade type ${t}: "${e.stat}" is not a player stat the editor knows`);
      }
      if (typeof u.icon !== 'string' || !u.icon) warn('no_icon', at, `Upgrade type ${t} names no icon`);
      else if (icons && !icons.has(u.icon)) warn('no_icon', at, `Upgrade type ${t}: no icon file art/ui/trail/${u.icon}.png`);
    }

    // the nodes
    if (!Array.isArray(data.nodes)) { err('nodes', null, 'nodes must be a list'); return out; }
    const ix = index(data);
    const seen = new Map();
    const broken = new Set();
    data.nodes.forEach((n, i) => {
      if (!isObj(n)) { err('node', null, `Node ${i + 1} in the file is not an object`); return; }
      const at = { id: typeof n.id === 'string' ? n.id : undefined, level: lvl(n) || undefined };
      if (typeof n.id !== 'string' || !/^[A-Za-z0-9_]+$/.test(n.id)) { err('id', at, `Node ${i + 1} in the file needs an id (letters, digits, _)`); return; }
      if (seen.has(n.id)) { err('duplicate_id', at, `Two nodes share the id ${n.id} (levels ${lvl(seen.get(n.id)) || '?'} and ${lvl(n) || '?'})`); broken.add(n.id); } else seen.set(n.id, n);
      if (!lvl(n)) { err('level', at, `${n.id}: level must be a whole number, 1 or more`); broken.add(n.id); }
      if (!KINDS.includes(n.kind)) { err('kind', at, `${n.id}: kind must be node, choice or optional`); broken.add(n.id); }
      if (n.kind === 'choice' && (n.group == null || n.group === '')) err('group', at, `${n.id} is a choice without a group`);
      if (n.kind !== 'choice' && n.group != null && n.group !== '') warn('group', at, `${n.id} has a group but is not a choice (the group is ignored)`);
      if (n.need != null && n.need !== 'all' && n.need !== 'any') err('need', at, `${n.id}: need must be all or any`);
      if (n.from != null && (!Array.isArray(n.from) || n.from.some((f) => typeof f !== 'string'))) { err('from', at, `${n.id}: from must be a list of node ids`); broken.add(n.id); }
      if (n.price != null && (!isNum(n.price) || n.price < 0)) err('price', at, `${n.id}: price must be a number, 0 or more`);
      if (n.price_mult != null && (!isNum(n.price_mult) || n.price_mult <= 0)) err('price', at, `${n.id}: price_mult must be a number above 0`);
      if (n.x != null && (!isNum(n.x) || n.x < 0 || n.x > 1)) err('x', at, `${n.id}: x must be between 0 and 1`);
      else if (isNum(n.x) && n.x > FREE_X) warn('x', at, `${n.id}: x ${n.x} sits in the right quarter the screen keeps free`);
      const g = n.gives;
      if (!isObj(g) || !GIVES.includes(g.type)) { err('gives', at, `${n.id}: gives.type must be one of ${GIVES.join(', ')}`); return; }
      if (g.type === 'upgrade') {
        const u = ups[g.upgrade];
        if (!isObj(u)) err('unknown_id', at, `${n.id}: unknown upgrade type "${g.upgrade == null ? '' : g.upgrade}"`);
        else if (u.kind !== 'word' && !isNum(g.value)) err('value', at, `${n.id}: ${g.upgrade} needs a value`);
        else if (isNum(g.value) && g.value === 0) warn('value', at, `${n.id}: a value of 0 gives nothing`);
      } else if (g.type === 'stage') {
        if (typeof g.map !== 'string' || typeof g.stage !== 'string' || !g.map || !g.stage) err('gives', at, `${n.id}: a stage node needs map and stage`);
        else if (P && Array.isArray(P.maps)) {
          const m = P.maps.find((x) => x.id === g.map);
          if (!m) err('unknown_id', at, `${n.id}: unknown map "${g.map}"`);
          else if (!(m.stages || []).some((s) => s.id === g.stage)) err('unknown_id', at, `${n.id}: map ${g.map} has no stage "${g.stage}"`);
        }
      } else {
        const key = { outlaw: 'outlaws', skin: 'skins', weapon: 'weapons', passive: 'passives', map: 'maps', structure: 'structures', powerup: 'powerups', feature: 'features' }[g.type];
        const known = ids(key);
        if (typeof g.id !== 'string' || !g.id) err('gives', at, `${n.id}: ${g.type} needs an id`);
        else if (known && !known.has(g.id)) err('unknown_id', at, `${n.id}: unknown ${GIVE_WORDS[g.type].toLowerCase()} "${g.id}"`);
      }
    });

    // a thing given by two nodes
    const given = new Map();
    for (const n of ix.nodes) {
      const g = n.gives;
      if (!isObj(g) || g.type === 'upgrade' || !GIVES.includes(g.type) || typeof n.id !== 'string') continue;
      const key = g.type + ':' + giveWhat(g);
      if (given.has(key)) err('given_twice', { id: n.id, level: lvl(n) || undefined }, `${n.id} and ${given.get(key)} both give ${g.type} ${giveWhat(g)}`);
      else given.set(key, n.id);
    }

    // levels
    for (let l = 1; l <= ix.max; l++) {
      const list = ix.byLevel.get(l) || [];
      if (!list.some(required)) err('no_required', { level: l }, list.length ? `Level ${l} has only optional nodes: the Trail Level could never pass it by a purchase` : `Level ${l} has no node`);
      if (list.length > 4) warn('crowded', { level: l }, `Level ${l} has ${list.length} nodes: the screen has places for four`);
    }

    // choice groups
    const named = new Map();
    for (const members of ix.groups.values()) {
      const g = String(members[0].group), l = lvl(members[0]);
      const at = { id: members[0].id, level: l || undefined, group: g };
      if (!named.has(g)) named.set(g, []);
      named.get(g).push(l);
      if (members.length < 2) err('group_size', at, `Choice group ${g} on level ${l} has one member (${members[0].id}): a choice is 2 to 4`);
      if (members.length > 4) err('group_size', at, `Choice group ${g} on level ${l} has ${members.length} members: a choice is 2 to 4`);
      for (const m of members) if (isObj(m.gives) && m.gives.type !== 'upgrade' && GIVES.includes(m.gives.type)) warn('unlock_in_choice', { id: m.id, level: lvl(m) || undefined }, `${m.id} unlocks ${m.gives.type} ${giveWhat(m.gives)} inside choice ${g}: a player who takes another member loses it for good`);
    }
    // a group's members share one level: the same name on two levels is two separate choices to the game
    for (const [g, levels] of named) if (levels.length > 1) warn('group_spread', { id: ix.groups.get(`${levels[1]}|${g}`)[0].id, level: levels[1], group: g }, `Choice group ${g} is spread over levels ${levels.slice().sort((a, b) => a - b).join(', ')}: the game reads each level's members as a choice of its own; give each its own name`);

    // from
    const from = resolveFrom(data, ix);
    for (const n of ix.nodes) {
      if (typeof n.id !== 'string' || !Array.isArray(n.from) || broken.has(n.id)) continue;
      const at = { id: n.id, level: lvl(n) || undefined };
      const dup = new Set();
      for (const f of n.from) {
        if (dup.has(f)) { warn('from', at, `${n.id} lists ${f} twice in from`); continue; }
        dup.add(f);
        const m = ix.byId.get(f);
        if (f === n.id) { err('from_level', at, `${n.id} connects from itself`); broken.add(n.id); continue; }
        if (!m) { err('unknown_id', at, `${n.id}: from names ${f}, which is no node`); broken.add(n.id); continue; }
        const same = lvl(m) === lvl(n);
        if (lvl(m) > lvl(n) || (same && required(n))) { err('from_level', at, `${n.id} (level ${lvl(n)}) connects from ${f} on level ${lvl(m)}: a node connects from a level below${required(n) ? '' : ' (an optional node also from its own)'}`); broken.add(n.id); }
        if (required(n) && !required(m)) warn('needs_optional', at, `${n.id} is required but depends on the optional node ${f}: skipping ${f} blocks the Trail`);
      }
    }

    // a node nobody can reach: its from asks for two members of one choice, or for a node that cannot be reached
    const memo = new Map(), visiting = new Set();
    const merge = (a, c) => { for (const [g, m] of c) { if (a.has(g) && a.get(g) !== m) return null; a.set(g, m); } return a; };
    const commits = (id) => {
      if (memo.has(id)) return memo.get(id);
      const n = ix.byId.get(id);
      if (!n || visiting.has(id)) return null;
      visiting.add(id);
      let got = new Map();
      if (inGroup(n)) got.set(groupKey(n), n.id);
      const f = from[id];
      const term = (t) => commits(t.ids[0]);
      if (f && f.terms.length) {
        if (f.need === 'any') {
          let ok = null;
          for (const t of f.terms) { const c = term(t); const m = c && merge(new Map(got), c); if (m) { ok = m; break; } }
          got = ok;
        } else for (const t of f.terms) { const c = term(t); got = c ? merge(got, c) : null; if (!got) break; }
      }
      visiting.delete(id);
      memo.set(id, got);
      return got;
    };
    for (const n of ix.nodes) {
      if (typeof n.id !== 'string' || broken.has(n.id) || ix.byId.get(n.id) !== n) continue;
      if (!commits(n.id)) err('unreachable', { id: n.id, level: lvl(n) || undefined }, `${n.id} can never be bought: what it connects from cannot all be bought (two members of one choice, or a node that is itself out of reach)`);
    }
    return out;
  }
  const errorsOf = (issues) => issues.filter((x) => x.sev === 'error');

  // ------------------------------------------------------------------ CSV

  function byLevelOrder(nodes) { return nodes.map((n, i) => [n, i]).sort((a, b) => (lvl(a[0]) || 1e9) - (lvl(b[0]) || 1e9) || a[1] - b[1]).map((x) => x[0]); }
  function csvCell(v, sep) {
    const s = v == null ? '' : String(v);
    return s.includes(sep) || /["\r\n]/.test(s) || /^\s|\s$/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  }
  /** One row per node in level order; the last two columns are read-only (the resolved price, the running total of
   *  every row's price). `o.bom` (default true) leads with a byte order mark so a spreadsheet reads the names right. */
  function toCsv(data, o) {
    const opt = o || {};
    const sep = opt.sep || ',';
    const lines = [CSV_COLS.join(sep)];
    let cum = 0;
    for (const n of byLevelOrder((data.nodes || []).filter(isObj))) {
      const g = isObj(n.gives) ? n.gives : {};
      const p = priceOf(data, n);
      cum += p;
      const row = [n.id, n.level, n.kind, n.group, Array.isArray(n.from) ? n.from.join(' ') : '', n.need, g.type, giveWhat(g), g.value, n.price, n.price_mult, n.x, n.name, n.note, p, cum];
      lines.push(row.map((v) => csvCell(v, sep)).join(sep));
    }
    return (opt.bom === false ? '' : '﻿') + lines.join('\n') + '\n';
  }

  function parseCsv(text) {
    let s = String(text || '');
    if (s.charCodeAt(0) === 0xFEFF) s = s.slice(1);
    const head = s.split(/\r?\n/, 1)[0] || '';
    const count = (c) => head.split(c).length - 1;
    const sep = count(';') > count(',') && count(';') >= count('\t') ? ';' : count('\t') > count(',') ? '\t' : ',';
    const rows = [];
    let row = [], cell = '', quoted = false, i = 0, had = false;
    const endCell = () => { row.push(cell); cell = ''; had = false; };
    const endRow = () => { endCell(); rows.push(row); row = []; };
    while (i < s.length) {
      const c = s[i];
      if (quoted) {
        if (c === '"') { if (s[i + 1] === '"') { cell += '"'; i += 2; continue; } quoted = false; i++; continue; }
        cell += c; i++; continue;
      }
      if (c === '"' && cell === '' && !had) { quoted = true; had = true; i++; continue; }
      if (c === sep) { endCell(); i++; continue; }
      if (c === '\r') { i++; continue; }
      if (c === '\n') { endRow(); i++; continue; }
      cell += c; i++;
    }
    if (cell !== '' || row.length) endRow();
    return { sep, rows: rows.filter((r) => r.some((x) => String(x).trim() !== '')) };
  }

  function setKey(node, key, value) {
    if (value === undefined || value === '' || value === null) delete node[key]; else node[key] = value;
  }
  function ordered(node) {
    const out = {};
    for (const k of NODE_KEYS) if (k in node) out[k] = node[k];
    for (const k of Object.keys(node)) if (!(k in out)) out[k] = node[k];
    return out;
  }

  /** A CSV back as nodes. A known id keeps its node's own key order and any key the table has no column for; a row
   *  without an id gets the next free one. -> {nodes, problems: [words], sep, rows, new_ids}. */
  function fromCsv(text, data) {
    const { sep, rows } = parseCsv(text);
    const problems = [];
    if (!rows.length) return { nodes: [], problems: ['The file has no rows'], sep, rows: 0, new_ids: [] };
    const head = rows[0].map((h) => String(h).trim().toLowerCase());
    const col = (name) => head.indexOf(name);
    for (const need of ['level', 'gives_type', 'gives_what']) if (col(need) < 0) problems.push(`The header has no "${need}" column (the first line must name the columns: ${CSV_COLS.join(', ')})`);
    if (problems.length) return { nodes: [], problems, sep, rows: rows.length - 1, new_ids: [] };
    const extra = head.filter((h) => h && !CSV_COLS.includes(h));
    if (extra.length) problems.push(`Columns the Trail does not know were ignored: ${extra.join(', ')}`);
    const old = new Map(((data && data.nodes) || []).filter(isObj).map((n) => [n.id, n]));
    const num = (v, what, line) => {
      let s = String(v == null ? '' : v).trim();
      if (s === '') return undefined;
      const pct = /%$/.test(s);
      s = s.replace(/%$/, '').replace(/\s/g, '');
      if (sep !== ',' || /^-?\d+,\d+$/.test(s)) s = s.replace(',', '.');
      const n = Number(s);
      if (!Number.isFinite(n) || s === '') { problems.push(`Line ${line}: ${what} "${v}" is not a number`); return undefined; }
      return pct ? tidy(n / 100) : n;
    };
    const used = new Set(old.keys());
    const nodes = [], seen = new Set(), newIds = [];
    const scratch = { nodes: Array.from(old.values()) };
    for (let r = 1; r < rows.length; r++) {
      const line = r + 1;
      const get = (name) => { const c = col(name); return c < 0 ? undefined : String(rows[r][c] == null ? '' : rows[r][c]).trim(); };
      const has = (name) => col(name) >= 0;
      let id = get('id') || '';
      if (!id) { id = nextId(scratch, used); used.add(id); newIds.push(id); }
      if (seen.has(id)) { problems.push(`Line ${line}: the id ${id} is on an earlier line too`); continue; }
      seen.add(id); used.add(id);
      const base = old.has(id) ? clone(old.get(id)) : {};
      base.id = id;
      const level = num(get('level'), 'level', line);
      if (level !== undefined) base.level = level;
      if (has('kind')) base.kind = get('kind') || 'node'; else if (!base.kind) base.kind = 'node';
      if (has('group')) setKey(base, 'group', get('group'));
      if (has('from')) { const f = get('from').split(/[\s,;|]+/).filter(Boolean); setKey(base, 'from', f.length ? f : undefined); }
      if (has('need')) setKey(base, 'need', get('need'));
      const type = get('gives_type'), what = get('gives_what');
      const g = isObj(base.gives) && base.gives.type === type ? base.gives : { type };
      if (type === 'upgrade') { g.upgrade = what; if (has('value')) setKey(g, 'value', num(get('value'), 'value', line)); }
      else if (type === 'stage') { const cut = what.indexOf('/'); g.map = cut < 0 ? '' : what.slice(0, cut); g.stage = cut < 0 ? what : what.slice(cut + 1); }
      else g.id = what;
      base.gives = g;
      if (has('price')) setKey(base, 'price', num(get('price'), 'price', line));
      if (has('price_mult')) setKey(base, 'price_mult', num(get('price_mult'), 'price_mult', line));
      if (has('x')) setKey(base, 'x', num(get('x'), 'x', line));
      if (has('name')) setKey(base, 'name', get('name'));
      if (has('note')) setKey(base, 'note', get('note'));
      nodes.push(old.has(id) ? base : ordered(base));
    }
    return { nodes, problems, sep, rows: rows.length - 1, new_ids: newIds };
  }

  /** What an import would change: {added: [id], removed: [id], changed: [{id, keys}], same, moved}. */
  function diffNodes(before, after) {
    const a = new Map((before || []).filter(isObj).map((n) => [n.id, n]));
    const b = new Map((after || []).filter(isObj).map((n) => [n.id, n]));
    const added = [], removed = [], changed = [];
    let same = 0;
    for (const [id, n] of b) {
      if (!a.has(id)) { added.push(id); continue; }
      const o = a.get(id);
      const keys = Array.from(new Set(Object.keys(o).concat(Object.keys(n)))).filter((k) => JSON.stringify(o[k]) !== JSON.stringify(n[k]));
      if (keys.length) changed.push({ id, keys }); else same++;
    }
    for (const id of a.keys()) if (!b.has(id)) removed.push(id);
    const keep = (list, other) => list.filter((n) => isObj(n) && other.has(n.id)).map((n) => n.id).join(' ');
    const moved = keep(byLevelOrder((before || []).filter(isObj)), b) !== keep(byLevelOrder((after || []).filter(isObj)), a);
    return { added, removed, changed, same, moved };
  }

  // ------------------------------------------------------------------ edits (each changes `data` in place)

  /** The next free id n001, n002...: one past the highest number in use (and past `used`, the ids the page has ever
   *  seen, so a deleted node's id does not come back in the same session). */
  function nextId(data, used) {
    let hi = 0;
    const look = (id) => { const m = /^n(\d+)$/.exec(String(id)); if (m) hi = Math.max(hi, Number(m[1])); };
    for (const n of (data.nodes || [])) if (isObj(n)) look(n.id);
    if (used) for (const id of used) look(id);
    return 'n' + String(hi + 1).padStart(3, '0');
  }
  function sortNodes(data) { data.nodes = byLevelOrder(data.nodes.filter(isObj)); return data; }
  function firstUpgrade(data) { return Object.keys(isObj(data.upgrades) ? data.upgrades : {})[0] || ''; }

  function addNode(data, level, like, used) {
    const src = isObj(like) ? like : null;
    const n = { id: nextId(data, used), level, kind: src && src.kind === 'optional' ? 'optional' : 'node', gives: src && isObj(src.gives) ? clone(src.gives) : { type: 'upgrade', upgrade: firstUpgrade(data), value: 0.03 } };
    data.nodes.push(n);
    sortNodes(data);
    return n.id;
  }
  function duplicateNode(data, id, used) {
    const i = data.nodes.findIndex((n) => isObj(n) && n.id === id);
    if (i < 0) return null;
    const copy = clone(data.nodes[i]);
    copy.id = nextId(data, used);
    data.nodes.splice(i + 1, 0, copy);
    return copy.id;
  }
  function deleteNodes(data, ids) {
    const gone = new Set(ids);
    data.nodes = data.nodes.filter((n) => !(isObj(n) && gone.has(n.id)));
    for (const n of data.nodes) {
      if (!isObj(n) || !Array.isArray(n.from)) continue;
      const left = n.from.filter((f) => !gone.has(f));
      if (left.length !== n.from.length) { if (left.length) n.from = left; else delete n.from; }
    }
    return data;
  }
  function moveNode(data, id, by) {
    const n = data.nodes.find((x) => isObj(x) && x.id === id);
    if (!n || !lvl(n)) return false;
    const to = Math.max(1, n.level + by);
    if (to === n.level) return false;
    n.level = to;
    sortNodes(data);
    return true;
  }
  function shiftLevels(data, at, by) {
    for (const n of data.nodes) if (isObj(n) && lvl(n) >= at) n.level += by;
    for (const s of Array.isArray(data.sections) ? data.sections : []) if (isObj(s) && Number.isInteger(s.from) && s.from > 1 && s.from >= at) s.from = Math.max(1, s.from + by);
  }
  /** A new level at `at` with one plain node; every level from `at` up moves one higher (sections with them). */
  function insertLevel(data, at, used) {
    shiftLevels(data, at, 1);
    return addNode(data, at, null, used);
  }
  /** Level `at` and its nodes gone; every level above moves one lower. */
  function removeLevel(data, at) {
    deleteNodes(data, data.nodes.filter((n) => isObj(n) && lvl(n) === at).map((n) => n.id));
    shiftLevels(data, at + 1, -1);
    return data;
  }
  function renameId(data, from, to) {
    if (!/^[A-Za-z0-9_]+$/.test(String(to)) || data.nodes.some((n) => isObj(n) && n.id === to)) return false;
    for (const n of data.nodes) {
      if (!isObj(n)) continue;
      if (n.id === from) n.id = to;
      if (Array.isArray(n.from)) n.from = n.from.map((f) => (f === from ? to : f));
    }
    return true;
  }

  return {
    W, ROW, TILE, TILE4, RAIL, RAIL_THIN, DIAMOND, DIAMOND_SMALL, DIAMOND_X, FREE_X, AUTO_X, KINDS, GIVES, GIVE_WORDS, MOTIFS, VALUE_KINDS, NODE_KEYS, CSV_COLS, CSV_READ_ONLY, DEFAULT_PRICE,
    normalise, index, groupKey, resolveFrom, railIds, autoSlots, layout, place, links, railPoints, railRun, rails, diamondOf, choiceMarks, hexRgb, sectionsSorted, sectionAt, coloursAt, dependents, spread, evaluate, states,
    curvePrice, priceOf, totals, upgradeTotals, statTotals, fmtValue, parseValue, giveWhat, giveText, check, errorsOf,
    toCsv, parseCsv, fromCsv, diffNodes, nextId, sortNodes, addNode, duplicateNode, deleteNodes, moveNode, insertLevel, removeLevel, renameId, ordered,
  };
})();
if (typeof module !== 'undefined') {
  module.exports = TrailModel;
  if (require.main === module) {
    const fs = require('fs');
    const [file, picksFile] = process.argv.slice(2);
    if (!file) { console.error('usage: node trail_model.js <trail.json> [picks.json]'); process.exit(2); }
    const data = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^﻿/, ''));
    const picks = picksFile ? JSON.parse(fs.readFileSync(picksFile, 'utf8')) : null;
    const issues = TrailModel.check(data, picks);
    for (const x of issues) console.log(`${x.sev === 'error' ? 'ERROR' : 'warn '} ${x.text}`);
    const bad = TrailModel.errorsOf(issues).length;
    console.log(`${(data.nodes || []).length} nodes, ${bad} error${bad === 1 ? '' : 's'}, ${issues.length - bad} warning${issues.length - bad === 1 ? '' : 's'}`);
    process.exit(bad ? 1 : 0);
  }
}
