// Pass 84 (lane TIMELINE): the page-free maths behind the rebuilt Timeline's view lanes and its warnings, run under Node
// by selftest_TIMELINE84.py too. Nothing here touches the page: timeline.js hands in the map, the Spawned so far
// estimate (model.js spawnEstimate), the Sim's series and small callbacks (a creature's numbers), and draws what comes
// back. Garry (2026-10-16): "I would prefer the charts ... to be not too abstract. For example I won't know what
// intensity means unless there is some way for me to clearly read somewhere what it consists of": every number here is
// a count of creatures, a share of them, HP, damage or seconds, and the RECIPES below are the words the page prints in
// each chart's "What is this?" box (the selftest keeps them and the maths in step).
'use strict';

const TimelineModel = (() => {
  const isObj = (x) => x != null && typeof x === 'object' && !Array.isArray(x);
  const num = (v, d) => { const n = Number(v); return v == null || v === '' || !isFinite(n) ? d : n; };
  const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

  // ------------------------------------------------------------------ roles (the editor's colours; the game ignores `role`)

  /** A row's `role` (INTERFACES.md): only the editor reads it, to colour and group the rows. */
  const ROLES = [
    { v: '', label: 'untagged', color: '#77766f', help: 'no role set: drawn neutral grey' },
    { v: 'fodder', label: 'fodder', color: '#6f8fd8', help: 'the plain crowd the hero mows through' },
    { v: 'swarm', label: 'swarm', color: '#3fbf7f', help: 'a burst of many at once (what the SWARM events were)' },
    { v: 'tank', label: 'tank', color: '#c27c3a', help: 'slow and tough: soaks the hero\'s damage' },
    { v: 'ranged', label: 'ranged', color: '#b26bd6', help: 'shoots from a distance (spit, rockets, snipers)' },
    { v: 'elite', label: 'elite', color: '#e6a04a', help: 'coloured elites: creatures wearing an elite modifier' },
    { v: 'special', label: 'special', color: '#e0609a', help: 'coloured specials: x15 HP, a glowing rim' },
  ];
  const ROLE_IDS = ROLES.map((r) => r.v).filter(Boolean);
  const roleOf = (r) => (isObj(r) && ROLE_IDS.includes(String(r.role)) ? String(r.role) : '');
  const roleInfo = (v) => ROLES.find((x) => x.v === (v || '')) || ROLES[0];
  const roleColor = (v) => roleInfo(v).color;

  /** A role from the row's own keys and its creature, for "Suggest roles" (the page asks before it writes any): an elite
   *  or special flag, a burst (once / no cap / a ring), a creature with a ranged / artillery / sniper block, a heavy body,
   *  else fodder. `c` the creature record (the server's), may be null. */
  function suggestRole(r, c) {
    if (!isObj(r)) return '';
    if (r.special === true) return 'special';
    if (r.elite != null && r.elite !== '') return 'elite';
    if (String(r.pace) === 'once' || r.respect_cap === false) return 'swarm';
    if (c && (isObj(c.ranged) && Object.keys(c.ranged).length || isObj(c.artillery) && Object.keys(c.artillery).length || isObj(c.sniper) && Object.keys(c.sniper).length)) return 'ranged';
    const hp = c ? num(c.hp, 0) : 0;
    if (c && (hp >= 60 || num(c.cap_share, 1) > 1)) return 'tank';
    return 'fodder';
  }

  // ------------------------------------------------------------------ a row's schedule in words

  /** "continuous" | "waves" | "once" (INTERFACES.md; anything else plays continuous). */
  function paceOf(r) {
    const p = isObj(r) ? String(r.pace == null ? '' : r.pace) : '';
    return p === 'waves' || p === 'once' ? p : 'continuous';
  }
  /** [lo, hi] seconds between a waves row's waves (`every` a number or [min, max]; empty = 30). */
  function everyRange(r) {
    const e = isObj(r) ? r.every : null;
    if (Array.isArray(e) && e.length) {
      const lo = num(e[0], 30), hi = num(e[e.length - 1], lo);
      return [Math.min(lo, hi), Math.max(lo, hi)];
    }
    const v = num(e, 30);
    return [v, v];
  }
  /** "12 every 15 s", "12 every 60–90 s", "once 24", "≈40/min" (a continuous row: what the estimate says it spawned over
   *  its open minutes, `perMin` handed in; null = not drawn yet). `count` the creatures a wave brings. */
  function quantityText(r, count, perMin) {
    const p = paceOf(r);
    const n = Math.max(1, Math.round(num(count, 1)));
    if (p === 'once') return `once ${n}`;
    if (p === 'waves') {
      const [lo, hi] = everyRange(r);
      if (!(hi > 0)) return `once ${n}`;
      const ev = lo === hi ? `${fmt(lo)} s` : `${fmt(lo)}–${fmt(hi)} s`;
      return `${n} every ${ev}` + (r.trickle ? ' + drawn' : '');
    }
    if (perMin == null) return 'continuous';
    return `≈${perMin >= 10 ? Math.round(perMin) : fmt(perMin)}/min`;
  }
  const fmt = (v) => { const x = Math.round(Number(v) * 10) / 10; return String(x); };

  // ------------------------------------------------------------------ the estimate, read per second

  /** The kill rate the estimate played at run second t (its `assume.turnover`: a number, a list per stage, or [[t, rate],
   *  ...] points), never above 1. `stageOf(t)` the 0-based stage. */
  function turnoverAt(turnover, t, stage) {
    const tv = turnover;
    if (Array.isArray(tv) && tv.length && Array.isArray(tv[0])) {
      const pts = tv.filter((q) => Array.isArray(q) && q.length >= 2).map((q) => [num(q[0], 0), Math.max(num(q[1], 0), 0)]);
      if (!pts.length) return 0;
      if (t <= pts[0][0]) return Math.min(pts[0][1], 1);
      for (let i = 1; i < pts.length; i++) {
        if (t <= pts[i][0]) {
          const [a, va] = pts[i - 1], [b, vb] = pts[i];
          return Math.min(b > a ? va + (vb - va) * (t - a) / (b - a) : vb, 1);
        }
      }
      return Math.min(pts[pts.length - 1][1], 1);
    }
    if (Array.isArray(tv) && tv.length) return Math.min(Math.max(num(tv[Math.min(Math.max(stage, 0), tv.length - 1)], 0.06), 0), 1);
    return Math.min(Math.max(num(tv, 0.06), 0), 1);
  }

  /** Who is alive at each of the estimate's points, by source and by creature. The estimate keeps the crowd as one pool
   *  per creature and load and kills the same share of every pool each second (the kill rate), so a source's living
   *  creatures follow alive(t) = alive(t − 1) × (1 − kill rate)^seconds + spawned since, and every point is scaled so the
   *  sources add up to the estimate's own alive count (its specials and boss fights make small differences).
   *  `est` model.js's estimate; `srcCreature(key)` the creature id of a source key ('roster:3', 'wave:0:1'); `stageAt(t)`.
   *  Returns {n (points), t[], alive[], src {key: Float64Array}, id {id: Float64Array}, col {id: Float64Array}: the
   *  coloured specials alive by creature}. Sources: every 'roster:<i>' / 'wave:<i>:<k>' key, and for what came some other
   *  way (swarm events, coloured elites, Elites, specials, bosses, minions, the portal wave) 'other:<id>'. When the
   *  estimate brings its own per-point `alive_src` (lane SPAWN), that is used as it is. */
  function aliveSeries(est, srcCreature, stageAt) {
    const pts = est && Array.isArray(est.points) ? est.points : [];
    const n = pts.length;
    const out = { n, t: new Float64Array(n), alive: new Float64Array(n), src: {}, id: {}, col: {} };
    if (!n) return out;
    const turnover = est.assume ? est.assume.turnover : 0.06;
    const srcKeys = new Set(), ids = new Set();
    for (const p of pts) {
      for (const k of Object.keys(p.src || {})) srcKeys.add(k);
      for (const id of Object.keys(p.by || {})) ids.add(id);
      if (p.alive_src) for (const k of Object.keys(p.alive_src)) srcKeys.add(k);
    }
    const keyId = {};
    for (const k of srcKeys) keyId[k] = srcCreature(k) || '';
    // a source that brings several creatures (a list, the roster draw) is filed under its creatures' 'other:<id>'
    for (const k of [...srcKeys]) if (!keyId[k]) { srcKeys.delete(k); delete keyId[k]; }
    const otherKeys = [...ids].map((id) => 'other:' + id);
    for (const k of otherKeys) keyId[k] = k.slice(6);
    const keys = [...srcKeys, ...otherKeys];
    for (const k of keys) out.src[k] = new Float64Array(n);
    for (const id of ids) { out.id[id] = new Float64Array(n); out.col[id] = new Float64Array(n); }
    const cur = {}, colCur = {};
    for (const k of keys) cur[k] = 0;
    for (const id of ids) colCur[id] = 0;
    // a source's cumulative spawns at point p ('other:<id>': the creature's spawns less its sources')
    const cumOf = (p) => {
      const c = {};
      const bySrcId = {};
      for (const k of srcKeys) {
        const v = num((p.src || {})[k], 0);
        c[k] = v;
        const id = keyId[k];
        bySrcId[id] = (bySrcId[id] || 0) + v;
      }
      for (const id of ids) {
        const tot = p.by && p.by[id] ? num(p.by[id][0], 0) : 0;
        c['other:' + id] = Math.max(tot - (bySrcId[id] || 0), 0);
      }
      return c;
    };
    let prev = null, prevCol = null, prevT = 0;
    for (let j = 0; j < n; j++) {
      const p = pts[j];
      const t = num(p.t, 0);
      const cum = cumOf(p);
      const colCum = {};
      for (const id of ids) colCum[id] = p.by && p.by[id] ? num(p.by[id][1], 0) : 0;
      const dt = prev ? Math.max(t - prevT, 0) : 0;
      const keep = prev ? Math.pow(1 - turnoverAt(turnover, t, stageAt ? stageAt(t) : 0), dt) : 1;
      for (const k of keys) cur[k] = cur[k] * keep + Math.max(cum[k] - (prev ? prev[k] : 0), 0);
      for (const id of ids) colCur[id] = colCur[id] * keep + Math.max(colCum[id] - (prevCol ? prevCol[id] : 0), 0);
      if (p.alive_src && isObj(p.alive_src)) {
        // lane SPAWN's own per-source alive count wins where it is given
        for (const k of keys) cur[k] = 0;
        for (const [k, v] of Object.entries(p.alive_src)) if (k in cur) cur[k] = Math.max(num(v, 0), 0);
      }
      if (isObj(p.aliveBy)) {
        // lane SPAWN's estimate keeps each creature's living count (pass 84: `aliveBy`, its lifetimes and kill rate in
        // it): each creature's sources are scaled to it, so only the split between the rows bringing the same creature
        // comes from the recurrence above
        const sumId = {};
        for (const k of keys) sumId[keyId[k]] = (sumId[keyId[k]] || 0) + cur[k];
        for (const k of keys) {
          const id = keyId[k];
          const want = Math.max(num(p.aliveBy[id], 0), 0);
          if (sumId[id] > 1e-9) cur[k] *= want / sumId[id];
          else if (k === 'other:' + id) cur[k] = want;
        }
        for (const id of ids) { const want = Math.max(num(p.aliveBy[id], 0), 0); if (colCur[id] > want) colCur[id] = want; }
      }
      let sum = 0;
      for (const k of keys) sum += cur[k];
      const target = isObj(p.aliveBy) ? sum : num(p.alive, sum);
      const s = sum > 1e-9 ? target / sum : 0;
      if (s !== 1 && sum > 1e-9) { for (const k of keys) cur[k] *= s; for (const id of ids) colCur[id] *= s; }
      out.t[j] = t;
      out.alive[j] = target;
      for (const k of keys) { out.src[k][j] = cur[k]; out.id[keyId[k]] && (out.id[keyId[k]][j] += cur[k]); }
      for (const id of ids) out.col[id][j] = Math.min(colCur[id], out.id[id][j]);
      prev = cum; prevCol = colCum; prevT = t;
    }
    out.keyId = keyId;
    return out;
  }

  /** The point index at run second t (the last at or before it; at a boss fight's own second the point after the fight,
   *  as model.js estimateAt). */
  function indexAt(ser, t) {
    const n = ser.n;
    if (!n) return -1;
    if (t < ser.t[0]) return 0;
    let lo = 0, hi = n - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (ser.t[mid] <= t) lo = mid; else hi = mid - 1;
    }
    return lo;
  }

  /** The creatures alive at point j, largest first: [{id, n, share}] (share of all alive). */
  function compositionAt(ser, j) {
    if (j < 0 || j >= ser.n) return [];
    const all = ser.alive[j];
    const out = [];
    for (const [id, arr] of Object.entries(ser.id)) if (arr[j] > 1e-6) out.push({ id, n: arr[j], share: all > 0 ? arr[j] / all : 0 });
    out.sort((a, b) => b.n - a.n || (a.id < b.id ? -1 : 1));
    return out;
  }

  /** What was spawned between two of the estimate's points, by creature: [{id, n, share}] largest first (the
   *  Composition lane's "spawned in the past N s" mode). */
  function spawnedBetween(est, a, b) {
    if (!a || !b) return [];
    const out = [];
    let all = 0;
    for (const id of Object.keys(b.by || {})) {
      const d = Math.max(num(b.by[id][0], 0) - (a.by && a.by[id] ? num(a.by[id][0], 0) : 0), 0);
      if (d > 1e-6) { out.push({ id, n: d, share: 0 }); all += d; }
    }
    for (const o of out) o.share = all > 0 ? o.n / all : 0;
    out.sort((x, y) => y.n - x.n || (x.id < y.id ? -1 : 1));
    return out;
  }

  // ------------------------------------------------------------------ On screen: the cap in bodies, cap full, starving rows

  /** The regular channel's load at point j (each creature alive × its cap share; the hell channel's rows apart) and the
   *  bodies it holds. `shareOf(id)` the creature's cap_share (default 1; the fodder 0.5), `hellKey(key)` true for a hell
   *  row's source. {load, bodies, hellLoad, hellBodies}. */
  function loadAt(ser, j, shareOf, hellKey) {
    let load = 0, bodies = 0, hl = 0, hb = 0;
    for (const [k, arr] of Object.entries(ser.src)) {
      const v = arr[j];
      if (!(v > 1e-9)) continue;
      const sh = Math.max(num(shareOf(ser.keyId[k]), 1), 0.05);
      if (hellKey && hellKey(k)) { hl += v * sh; hb += v; } else { load += v * sh; bodies += v; }
    }
    return { load, bodies, hellLoad: hl, hellBodies: hb };
  }

  /** The cap as bodies at the crowd's mix: cap ÷ (load per body). With nobody alive, the cap ÷ `defShare`. */
  function capBodies(cap, load, bodies, defShare) {
    const per = bodies > 1e-6 ? load / bodies : Math.max(num(defShare, 1), 0.05);
    return per > 1e-6 ? cap / per : cap;
  }

  // pass 103 (lane LE; Garry: "I specify the cap to be something (mostly just 500 all the way through) and then the `cap
  // in bodies` line ... gives me a different set of numbers that don't match. Which is the correct one?"): both, in
  // different units. The cap counts LOAD (each creature its cap_share: a goblin 0.5, the Hammer Giant 2.5), the hard cap
  // counts BODIES, and the crowd is held under the lower of the two: the effective limit, drawn on the On screen lane.
  /** The crowd's limit at one second. `cap` in load units, `load`/`bodies` the regular crowd then, `hard` the map's
   *  hard_cap in bodies (none = Infinity). {cap, per (load a body at the mix), capBodies, hard, limit (bodies), binds
   *  'cap' | 'hard'}: a tie is the cap's. */
  function effectiveLimit(cap, load, bodies, hard, defShare) {
    const per = bodies > 1e-6 ? load / bodies : Math.max(num(defShare, 1), 0.05);
    const cb = capBodies(num(cap, 0), load, bodies, defShare);
    const h = num(hard, 0) > 0 ? num(hard, 0) : Infinity;
    return { cap: num(cap, 0), per, capBodies: cb, hard: h, limit: Math.min(cb, h), binds: cb <= h ? 'cap' : 'hard' };
  }

  /** Whether the cap ever binds, per window. `limits` [{t, binds, capBodies, hard, per, alive}] (one a second of the
   *  estimate), `windows` [{i, a, b}] (run seconds, a stage each). Per window: {i, a, b, n, capSecs, hardSecs, never (the
   *  cap binds at no second), minCapBodies (the fewest bodies the cap held), per (the median load a body while anyone
   *  is alive, else 1), capToBind (the cap in load units under which it starts to count: hard × per, rounded down)}. */
  function capBinding(limits, windows) {
    return (windows || []).map((w) => {
      let n = 0, capSecs = 0, hardSecs = 0, minCb = Infinity, hard = Infinity;
      const pers = [];
      for (const L of limits || []) {
        if (!(L.t >= w.a && L.t < w.b)) continue;
        n++;
        if (L.binds === 'cap') capSecs++; else hardSecs++;
        if (L.capBodies < minCb) minCb = L.capBodies;
        if (isFinite(L.hard)) hard = Math.min(hard, L.hard);
        if (num(L.alive, 0) >= 1) pers.push(L.per);
      }
      pers.sort((p, q) => p - q);
      const per = pers.length ? pers[Math.floor(pers.length / 2)] : 1;
      return { i: w.i, a: w.a, b: w.b, n, capSecs, hardSecs, never: n > 0 && capSecs === 0, minCapBodies: minCb, per,
        hard, capToBind: isFinite(hard) ? Math.floor(hard * per) : null };
    });
  }

  /** The Composition lane's colour of a creature: its own (`colorOf`, App.creatureColor) when it is one of the lane's
   *  layers (`shown`, the ten largest over the view), the "every other creature" grey when the lane folds it into others. */
  const OTHER_COLOR = '#5a5955';
  /** The Composition lane's layers' colours, all different: each creature keeps its own (`colorOf`) unless an earlier
   *  (larger) layer already has that colour; then it takes the first `palette` colour no layer uses yet (the page's
   *  creature colours repeat after 16 creatures, so two layers could share one). {id: colour}. */
  function compPalette(shown, colorOf, palette) {
    const out = {}, used = new Set();
    for (const id of shown || []) {
      let c = colorOf(id);
      if (used.has(c)) c = (palette || []).find((p) => !used.has(p) && p !== OTHER_COLOR) || c;
      out[id] = c;
      used.add(c);
    }
    return out;
  }
  function compColor(id, shown, colorOf, folded) {
    if (id === '__other') return OTHER_COLOR;
    if (shown && folded && !shown.includes(id)) return OTHER_COLOR;
    return colorOf(id);
  }

  /** Seconds where the regular channel's load sits at the cap: load ≥ cap × FULL_AT (the estimate refills every spawn
   *  check, so a full cap reads a hair under it). */
  const FULL_AT = 0.97;

  /** The rows that wanted to spawn and could not at point j: open, in the continuous draw with a weight above 0, and
   *  spawning nothing in the STARVE_S seconds before while the cap was full all that time. `rows` [{key, open(t) -> bool,
   *  drawn, weight(t)}]; `fullAt(j)` bool. Lane SPAWN's own `starving` list on the point wins where it is given. */
  const STARVE_S = 5;
  const STARVE_SHARE = 0.25;
  function starvingAt(est, ser, j, rows, fullAt) {
    const p = est.points[j];
    if (p && Array.isArray(p.starving)) return p.starving.slice();
    // lane SPAWN's estimate (pass 84): `starve` {'roster:<i>': the share of that second's spawn checks the row wanted to
    // spawn and was cut}; a row counts as starving at a quarter or more
    if (p && isObj(p.starve)) return Object.keys(p.starve).filter((k) => num(p.starve[k], 0) >= STARVE_SHARE).sort((a, b) => num(p.starve[b], 0) - num(p.starve[a], 0));
    if (!fullAt(j)) return [];
    const t = ser.t[j];
    let j0 = j;
    while (j0 > 0 && ser.t[j0 - 1] >= t - STARVE_S) { j0--; if (!fullAt(j0)) return []; }
    if (t - ser.t[j0] < STARVE_S - 1) return [];
    const a = est.points[j0], b = p;
    const out = [];
    for (const r of rows) {
      if (!r.drawn || !r.open(t) || !(r.weight(t) > 0)) continue;
      const got = num((b.src || {})[r.key], 0) - num((a.src || {})[r.key], 0);
      if (got < 0.05) out.push(r.key);
    }
    return out;
  }

  // ------------------------------------------------------------------ Challenge

  /** The Challenge lane's zones: seconds of the hero's damage to clear the screen. Under `easy` he mows it down, over
   *  `hard` the crowd outlasts him (the Sim's "Keeping up with the crowd" chart reads the same number). The page lets
   *  Garry move both limits (a page setting). */
  const ZONES = { easy: 10, hard: 30 };
  /** The same for the second measure, health bars lost clearing the screen (HP × bite ÷ (DPS × EHP), the Sim's
   *  "challenge"): under one bar easy, over three hard. */
  const BAR_ZONES = { easy: 1, hard: 3 };
  function zoneOf(seconds, z) {
    const zz = z || ZONES;
    if (seconds == null || !isFinite(seconds)) return '';
    return seconds < zz.easy ? 'easy' : seconds <= zz.hard ? 'fair' : 'hard';
  }

  /** The hero's power with no Sim: a typical curve (PowerModel.TYPICAL: 1 at the start, 3.5 at the King, 9 at the Gila,
   *  23 at the Brander); `marks` [{t, power}] in run seconds, straight between them on a log scale, the last step's growth
   *  going on past the last mark (never down). */
  function typicalPower(t, marks) {
    const m = (marks || []).filter((x) => isFinite(x.t) && x.power > 0).sort((a, b) => a.t - b.t);
    if (!m.length) return 1;
    if (t <= m[0].t) return m[0].power;
    for (let i = 1; i < m.length; i++) {
      if (t <= m[i].t) {
        const f = (t - m[i - 1].t) / Math.max(m[i].t - m[i - 1].t, 1e-9);
        return Math.exp(Math.log(m[i - 1].power) + f * (Math.log(m[i].power) - Math.log(m[i - 1].power)));
      }
    }
    const a = m[m.length - 2] || m[0], b = m[m.length - 1];
    const rate = m.length > 1 ? (Math.log(b.power) - Math.log(a.power)) / Math.max(b.t - a.t, 1e-9) : 0;
    return Math.exp(Math.log(b.power) + Math.max(rate, 0) * (t - b.t));
  }
  /** A typical hero from his power (power = √(DPS ÷ 20.4 × EHP ÷ 100), HeroPower): the Sims show his effective HP barely
   *  grows (the p83 Drifter: power 3.8 at 2:00 with 350 DPS and about 80 EHP), so the power's square goes to his damage:
   *  DPS = baseDps × power², EHP = baseEhp. {dps, ehp, power}. */
  function typicalHero(t, marks, baseDps, baseEhp) {
    const pw = typicalPower(t, marks);
    return { power: pw, dps: num(baseDps, 20.4) * pw * pw, ehp: num(baseEhp, 100) };
  }

  /** The crowd at point j in numbers: HP on screen (each source's living creatures × that source's HP in play; bosses
   *  left out, as the Sim's keep_up; a coloured special counts its special HP), the bite a second if all bit at once
   *  (ATK ÷ bite interval), the threat (Σ alive × HP × ATK ÷ bite interval). `numbers(key, t)` -> {hp, atk, bite, boss,
   *  spHp} for a source key. */
  function crowdAt(ser, j, numbers) {
    const t = ser.t[j];
    let hp = 0, bite = 0, threat = 0, n = 0;
    const byId = {};
    // the coloured specials' extra HP: each creature's living coloured ones, spread over its sources by their share
    for (const [k, arr] of Object.entries(ser.src)) {
      const v = arr[j];
      if (!(v > 1e-9)) continue;
      const x = numbers(k, t);
      if (!x || x.boss) continue;
      const id = ser.keyId[k];
      const all = ser.id[id] ? ser.id[id][j] : 0;
      const colN = all > 1e-9 && ser.col[id] ? ser.col[id][j] * (v / all) : 0;
      const h = v * x.hp + colN * x.hp * Math.max(num(x.spHp, 1) - 1, 0);
      const b = v * x.atk / Math.max(num(x.bite, 0.6), 0.05);
      hp += h; bite += b; threat += h * x.atk / Math.max(num(x.bite, 0.6), 0.05); n += v;
      const o = byId[id] || (byId[id] = { id, n: 0, hp: 0, bite: 0 });
      o.n += v; o.hp += h; o.bite += b;
    }
    const top = Object.values(byId).sort((a, b) => b.hp - a.hp);
    return { t, hp, bite, threat, n, top };
  }

  // ------------------------------------------------------------------ warnings

  /** Overlapping identical rows: the same creature, look, pacing, channel, pattern, enemy list and overrides, their spans
   *  overlapping. [[i, k]] pairs. */
  function overlappingTwins(roster, end) {
    const out = [];
    const sig = (r) => JSON.stringify([r.enemy, r.variant || '', paceOf(r), r.channel || 'regular', r.pattern || 'pack', r.every == null ? null : r.every, r.count == null ? null : r.count, r.elite || '', !!r.special, r.stats || {}, r.weights_list || null]);
    const span = (r) => [num(r.t, 0), r.until == null || r.until === '' ? end : num(r.until, end)];
    for (let i = 0; i < roster.length; i++) {
      for (let k = i + 1; k < roster.length; k++) {
        const a = roster[i], b = roster[k];
        if (!isObj(a) || !isObj(b) || sig(a) !== sig(b)) continue;
        const [a0, a1] = span(a), [b0, b1] = span(b);
        if (a0 < b1 && b0 < a1) out.push([i, k]);
      }
    }
    return out;
  }

  /** The floor above the cap: the first second the floor_curve asks for more bodies than the cap holds (in bodies at
   *  the crowd's mix, `capBodiesAt(t)`). Null when never. */
  function floorOverCap(floorAt, capBodiesAt, end, step) {
    const st = step || 5;
    for (let t = 0; t <= end; t += st) {
      const f = floorAt(t);
      if (f > 0 && f > capBodiesAt(t) + 0.5) return { t, floor: f, cap: capBodiesAt(t) };
    }
    return null;
  }

  /** The largest jump of a per-second series (the crowd's HP on screen) above `ratio` × the second before, skipping
   *  seconds where the series is under `min`: {t, from, to} or null. */
  function biggestJump(ts, vals, ratio, min) {
    let best = null;
    for (let j = 1; j < vals.length; j++) {
      const a = vals[j - 1], b = vals[j];
      if (!(a >= min) || !(b > a * ratio)) continue;
      if (ts[j] - ts[j - 1] > 1.5 || ts[j] === ts[j - 1]) continue;
      if (!best || b / a > best.to / best.from) best = { t: ts[j], from: a, to: b };
    }
    return best;
  }

  // ------------------------------------------------------------------ what each chart is made of (the "What is this?" boxes)

  const RECIPES = {
    onscreen: {
      what: 'How many creatures are alive at each second of the run clock: a count of bodies on the map.',
      lines: [
        ['estimate', 'the Spawned so far estimate\'s crowd: it plays the director\'s rules second by second (the cap, the weights, the spawn checks, the waves, every row\'s schedule) and assumes the hero kills the kill rate\'s share of the living crowd each second (the box in Ruler and controls).'],
        ['Sim', 'the run sim\'s real alive count (the average of its runs at each run second), dashed, when the map has a finished Sim (Ruler and controls picks which).'],
        ['cap', 'the map\'s cap curve turned into bodies: the cap counts load units (a creature counts its cap_share: the skeleton 0.5, so 100 of cap holds 200 skeletons), so the line is cap ÷ the average load per body alive then.'],
        ['limit', 'pass 103: the line drawn is the effective limit in bodies, the lower of the cap at the crowd\'s mix (above) and the hard cap (hard_cap, a count of bodies whatever their share). Where the hard cap is lower it is what holds the crowd and the cap curve changes nothing there (the Warnings say so); the hover names the one that binds.'],
        ['floor', 'the floor curve (floor_curve): the least creatures alive the director keeps on the regular channel; while fewer are alive it draws the continuous rows at once (within the cap).'],
        ['red', 'seconds where the regular channel\'s load is at the cap (97% of it or more): the director has no room, and rows that wanted to spawn starve. Hover a red stretch for the rows.'],
      ],
    },
    challenge: {
      what: 'How long the hero needs to kill everything on the screen with his own damage: seconds = the crowd\'s HP on screen ÷ the hero\'s damage a second.',
      lines: [
        ['crowd HP', 'every living creature (the estimate\'s crowd) × its HP in play: its row\'s HP fixed from the row\'s start (the creature\'s HP × the HP curve there, or the row\'s own), × the stage multiplier, × creature_hp_mult, × the hero level box; a coloured special counts its special HP. Bosses are left out.'],
        ['hero damage a second', 'the Sim\'s hero (his full DPS: every weapon\'s damage a second on one target that every shot hits) when a Sim is shown; else the Sim\'s real damage a second (an older Sim); with no Sim a typical hero: 20.4 × his power² (the power of the probe\'s tuned builds: 1 at the start, 3.5 at 7:10, 9 at 14:20, 23 at 21:30, straight between on a log scale; power = √(DPS ÷ 20.4 × EHP ÷ 100) and his effective HP barely grows in the Sims, so the square goes to his damage).'],
        ['Sim', 'dashed: the Sim\'s own "seconds to clear the crowd" (keep_up, the middle run: his real damage over the past 5 s, so it runs higher than his full DPS would say).'],
        ['zones', 'green under the easy limit (he mows the screen), amber up to the hard limit (the crowd lingers), red past it (the crowd outlasts him). The two limits are the boxes in this section\'s header (10 s and 30 s unless you change them).'],
        ['dots', 'red dots on the floor of the lane: the Sim\'s deaths (each run\'s, at its run second).'],
      ],
    },
    challenge_bars: {
      what: 'How many of the hero\'s health bars clearing the screen would cost him if every creature on it bit him the whole time: (seconds to clear the screen) × (the crowd\'s bite a second ÷ his effective HP) = the crowd\'s HP × bite ÷ (his damage a second × his effective HP). The Sim\'s "challenge" is the same sum.',
      lines: [
        ['crowd HP × bite', 'over every living creature (the estimate\'s crowd, bosses left out): its HP in play × its ATK ÷ its bite interval (contact_cd, 0.6 s for most): HP × damage a second.'],
        ['hero damage × effective HP', 'the Sim\'s hero: his full DPS on one target and his effective HP ((max HP + shield + 30 s of regen and lifesteal) ÷ ((1 − armour) × (1 − evade))); with no Sim a typical hero: 20.4 × power² and 100 (his effective HP barely grows in the Sims), the power of the probe\'s tuned builds (1, 3.5, 9, 23 at the stage marks).'],
        ['Sim', 'dashed: the Sim\'s own challenge (the middle run at each run second).'],
        ['zones', 'green under the easy limit, amber to the hard limit, red past it (1 and 3 bars unless you change them; each measure keeps its own pair).'],
        ['dots', 'red dots on the floor of the lane: the Sim\'s deaths.'],
      ],
    },
    composition: {
      what: 'Who the crowd is made of, as shares that add up to 100% at every second.',
      lines: [
        ['on screen', 'each creature\'s share of the creatures alive then (the estimate\'s crowd; the Sim\'s when "Sim" is picked).'],
        ['spawned', 'each creature\'s share of what spawned in the past N seconds (N is the "past" box in the top bar), the pass 83 window.'],
        ['colours', 'one colour per creature, the same as on the spawn rows when they are coloured by creature; the hover lists every creature with its count and share.'],
      ],
    },
  };

  const api = {
    ROLES, ROLE_IDS, roleOf, roleInfo, roleColor, suggestRole,
    paceOf, everyRange, quantityText,
    turnoverAt, aliveSeries, indexAt, compositionAt, spawnedBetween,
    loadAt, capBodies, effectiveLimit, capBinding, compColor, compPalette, OTHER_COLOR, FULL_AT, STARVE_S, STARVE_SHARE, starvingAt,
    ZONES, BAR_ZONES, zoneOf, typicalPower, typicalHero, crowdAt,
    overlappingTwins, floorOverCap, biggestJump, RECIPES,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  return api;
})();
