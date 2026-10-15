'use strict';
// Pass 82 (lane XP): the page-free maths of the XP a hero level needs, a copy of the game's game/core/data/XpCurve.gd
// (TYPES, DEFAULTS, type_of, params_of, need, total, the table's points, the guards) for the Settings tab's "XP per
// level" card (xp_card.js): the two charts, the levels a sim's XP reaches, and the page's checks. selftest_XP82.py runs
// it under Node and checks it against a Python copy of the GDScript and its DEFAULTS. L is the level the hero is at: level
// 1 needs need(1) XP to reach level 2. Everything here is before the map's xp_need_mult unless a name says otherwise.
const XpModel = (() => {
  const TYPES = ['quadratic', 'linear', 'exponential', 'power', 'table'];
  const DEFAULT_TYPE = 'quadratic';
  /** XpCurve.DEFAULTS: what a number the type's block leaves out plays (the quadratic's are today's curve). */
  const DEFAULTS = {
    quadratic: { base: 15.0, linear: 6.0, quad: 0.5 },
    linear: { base: 21.5, step: 16.5 },
    exponential: { base: 40.0, growth: 1.11, cap: 0.0 },
    power: { base: 6.5, power: 1.33 },
    table: { points: [[1, 21.5], [5, 57.5], [10, 125.0], [20, 335.0], [30, 645.0], [40, 1055.0], [50, 1565.0], [60, 2175.0]], after_growth: 0.025 },
  };
  const MIN_NEED = 0.01;
  const MAX_NEED = 1.0e12;
  /** The levels the checks walk for a zero or a negative (endless runs seldom pass 150), and the level under which a
   *  curve that reaches the game's most (MAX_NEED: the hero would stop levelling there) is worth a warning. */
  const CHECK_LEVELS = 300;
  const WALL_LEVEL = 150;

  const isObj = (x) => x != null && typeof x === 'object' && !Array.isArray(x);
  const isNum = (v) => typeof v === 'number';
  const clone = (x) => JSON.parse(JSON.stringify(x));
  // GDScript's round(): halves away from zero
  const gdRound = (x) => (x < 0 ? -Math.round(-x) : Math.round(x));

  /** XpCurve.type_of: the type the block names, the default when it names none or an unknown one. */
  function typeOf(curve) {
    const t = isObj(curve) && curve.type !== undefined ? String(curve.type) : DEFAULT_TYPE;
    return TYPES.includes(t) ? t : DEFAULT_TYPE;
  }

  /** XpCurve.params_of: the type's own numbers, DEFAULTS' where the block leaves one out or holds a non-number. */
  function paramsOf(curve, type) {
    const ty = TYPES.includes(type) ? type : typeOf(curve);
    const out = clone(DEFAULTS[ty]);
    const own = isObj(curve) ? curve[ty] : undefined;
    if (!isObj(own)) return out;
    for (const k of Object.keys(out)) {
      const v = own[k];
      if (k === 'points') { if (Array.isArray(v) && tablePoints(v).length) out[k] = v; }
      else if (isNum(v)) out[k] = Number(v);
    }
    return out;
  }

  /** XpCurve._table_points: [[level >= 1, XP], ...] sorted by level, one per level (the last listed wins). */
  function tablePoints(raw) {
    const by = new Map();
    for (const p of Array.isArray(raw) ? raw : []) {
      if (!Array.isArray(p) || p.length < 2) continue;
      if (!isNum(p[0]) || !isNum(p[1])) continue;
      by.set(Math.max(gdRound(p[0]), 1), Number(p[1]));
    }
    return [...by.keys()].sort((a, b) => a - b).map((lv) => [lv, by.get(lv)]);
  }

  function tableNeed(pts, afterGrowth, level) {
    if (!pts.length) pts = tablePoints(DEFAULTS.table.points);
    if (level <= pts[0][0]) return pts[0][1];
    for (let k = 1; k < pts.length; k++) {
      const a = pts[k - 1], b = pts[k];
      if (level <= b[0]) return a[1] + (b[1] - a[1]) * ((level - a[0]) / (b[0] - a[0]));
    }
    const last = pts[pts.length - 1];
    return last[1] * Math.pow(1 + afterGrowth, level - last[0]);
  }

  /** The formula before the guards (the checks look at it for zeros and overflows). */
  function rawNeed(curve, level) {
    const ty = typeOf(curve);
    const p = paramsOf(curve, ty);
    const L = Math.max(level, 1);
    switch (ty) {
      case 'linear': return p.base + p.step * (L - 1);
      case 'exponential': { const x = p.base * Math.pow(p.growth, L - 1); return p.cap > 0 ? Math.min(x, p.cap) : x; }
      case 'power': return p.base * Math.pow(L, p.power);
      case 'table': return tableNeed(tablePoints(p.points), p.after_growth, level);
      default: return p.base + p.linear * level + p.quad * level * level;
    }
  }

  function clean(x) {
    if (!isFinite(x)) return MAX_NEED;
    return Math.min(MAX_NEED, Math.max(MIN_NEED, x));
  }

  /** XpCurve.need: the XP level `level` needs to reach the next, before xp_need_mult. */
  const need = (curve, level) => clean(rawNeed(curve, level));

  /** XpCurve.total: the XP from level 1 to `level`, before the multiplier. */
  function total(curve, level) {
    let s = 0;
    for (let L = 1; L < level; L++) s += need(curve, L);
    return s;
  }

  /** The map's multiplier as Run.xp_need_mult reads it (1 when unset; never under 0.01). */
  function multOf(tl) {
    const raw = isObj(tl) ? tl.xp_need_mult : undefined;
    const v = raw == null || raw === '' ? 1 : Number(raw);
    return Math.max(isFinite(v) ? v : 1, 0.01);
  }

  /** The curve block of a timeline ({} when absent or not a block, as JsonContent reads it). */
  const curveOf = (tl) => (isObj(tl) && isObj(tl.xp_curve) ? tl.xp_curve : {});

  /** Levels 1..maxLevel with what each needs and what reaching it takes, both times `mult`:
   *  [{L, need: XP from L to L + 1, cum: XP from level 1 to reach L}]. */
  function series(curve, mult, maxLevel) {
    const out = [];
    let cum = 0;
    for (let L = 1; L <= maxLevel; L++) {
      const n = need(curve, L) * mult;
      out.push({ L, need: n, cum });
      cum += n;
    }
    return out;
  }

  /** The level `xp` XP in all buys from level 1, as Run.add_xp levels (a level comes when the XP reaches its need). */
  function levelAt(curve, mult, xp, maxLevel) {
    let L = 1, left = xp;
    const top = maxLevel || 100000;
    while (L < top) {
      const n = need(curve, L) * mult;
      if (left < n) break;
      left -= n;
      L++;
    }
    return L;
  }

  /** The first second a run whose XP in all is `xpByT` (one number a second, cumulative) reaches `level`; null when it
   *  never does in that run. */
  function secondsToLevel(curve, mult, xpByT, level) {
    const want = total(curve, level) * mult;
    if (!Array.isArray(xpByT)) return null;
    for (let t = 0; t < xpByT.length; t++) if (Number(xpByT[t]) >= want) return t;
    return null;
  }

  /** The page's checks of a timeline's curve: [{level: 'error' | 'warn', msg}]. Errors block Save: an unknown type, a
   *  block that is not a block, a level that would need 0 XP or less (the game would level on nothing; it plays 0.01), a
   *  number that is not a number, a table without a usable point, a negative cap. Warnings: a level under WALL_LEVEL that
   *  would need more than the game counts (MAX_NEED: the hero stops levelling there), a growth under 1, a level that
   *  needs less than the one before, a table point that is not [level, XP] (skipped), two points on one level, a key the
   *  type does not know. */
  function issues(tl) {
    const out = [];
    const err = (msg) => out.push({ level: 'error', msg });
    const warn = (msg) => out.push({ level: 'warn', msg });
    if (!isObj(tl) || tl.xp_curve == null) return out;
    const c = tl.xp_curve;
    if (!isObj(c)) { err('xp_curve must be a block {type, <type>: {numbers}} (the game plays today\'s curve)'); return out; }
    if (c.type != null && !TYPES.includes(String(c.type))) { err(`unknown growth type "${c.type}" (the game plays today's quadratic)`); return out; }
    for (const k of Object.keys(c)) if (k !== 'type' && !TYPES.includes(k)) warn(`"${k}" is not a growth type's block (the game ignores it)`);
    const ty = typeOf(c);
    const own = c[ty];
    if (own != null && !isObj(own)) { err(`the ${ty} numbers must be a block (the game plays its defaults)`); return out; }
    if (isObj(own)) {
      for (const k of Object.keys(own)) {
        if (!(k in DEFAULTS[ty])) warn(`${ty}: "${k}" means nothing to this type (the game ignores it)`);
        else if (k !== 'points' && !isNum(own[k])) err(`${ty}: ${k} is not a number (the game plays the default ${DEFAULTS[ty][k]})`);
      }
    }
    const p = paramsOf(c, ty);
    if (ty === 'table') {
      const raw = isObj(own) ? own.points : undefined;
      if (raw != null) {
        if (!Array.isArray(raw)) err('table: the levels must be a list of [level, XP]');
        else {
          const bad = raw.filter((q) => !Array.isArray(q) || q.length < 2 || !isNum(q[0]) || !isNum(q[1])).length;
          if (!tablePoints(raw).length) err('table: no [level, XP] point the game can read (it plays the default table)');
          else if (bad) warn(`table: ${bad} point${bad > 1 ? 's are' : ' is'} not [level, XP] (skipped)`);
          const lv = raw.filter((q) => Array.isArray(q) && isNum(q[0])).map((q) => Math.max(gdRound(q[0]), 1));
          if (new Set(lv).size < lv.length) warn('table: two points on one level (the last one counts)');
        }
      }
      if (p.after_growth < 0) warn('table: After the table is negative: every level past the table needs less than the one before');
    }
    if (ty === 'exponential') {
      if (p.cap < 0) err('exponential: the cap is negative (0 = no cap)');
      if (p.growth < 1 && p.growth > 0) warn(`exponential: growth ${p.growth} is under 1: every level needs less than the one before`);
    }
    const m = multOf(tl);
    let shrink = 0;
    for (let L = 1; L <= CHECK_LEVELS; L++) {
      const x = rawNeed(c, L);
      if (!(x > 0) && isFinite(x)) { err(`level ${L} would need ${fmt(x * m)} XP: 0 or less (the game makes it 0.01, the hero would level on nothing)`); break; }
      if (!isFinite(x) || x > MAX_NEED) { if (L < WALL_LEVEL) warn(`level ${L} would need more XP than the game counts (it caps a level at ${MAX_NEED.toExponential(0)}): the hero stops levelling there`); break; }
      if (!shrink && L > 1 && x < rawNeed(c, L - 1) - 1e-9) shrink = L;
    }
    if (shrink && !out.some((o) => o.level === 'error')) warn(`level ${shrink} needs less XP than level ${shrink - 1}`);
    return out;
  }

  function fmt(x) {
    if (!isFinite(x)) return String(x);
    return Math.abs(x) >= 100 ? Math.round(x).toLocaleString('en-US') : String(Math.round(x * 100) / 100);
  }

  const api = { TYPES, DEFAULT_TYPE, DEFAULTS, MIN_NEED, MAX_NEED, CHECK_LEVELS, WALL_LEVEL, typeOf, paramsOf, tablePoints, rawNeed, need, total, multOf, curveOf, series, levelAt, secondsToLevel, issues };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  return api;
})();
