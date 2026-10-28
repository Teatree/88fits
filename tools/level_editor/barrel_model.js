'use strict';
// Pass 112 (lane BARREL): the page-free maths of the map's barrels, a copy of game/core/systems/BarrelSpawns.gd's tables
// and rules (RESPAWN_DEFAULTS, CONTENT_DEFAULTS, respawn_of, contents_of, weight_list, turns_in) for the Settings tab's
// Barrels card (barrel_card.js) and the page's checks. selftest_BARREL112.py runs it under Node and checks its tables
// against the GDScript's. One block of timeline_data, `barrels`: {respawn: {...}, brown: {...}, black: {...}} (broken
// barrels laid again off the screen on a clock; each kind's power-up chance, which power-up, how far it is thrown, its
// gems and coins).
const BarrelModel = (() => {
  const RESPAWN_DEFAULTS = {
    enabled: false, first: 45, every: [40, 60], max_lying: 35, max_per_stage: 0,
    min_dist: 20, max_dist: 40, black_chance: 0.22, view_margin: 2,
    in_boss: true, in_portal: false, in_endless: false,
  };
  const CONTENT_DEFAULTS = {
    brown: { powerup_chance: 0, powerups: [], throw_distance: [5, 7], gems_small: 8, gems_medium: 0, coins: 0 },
    black: { powerup_chance: 0, powerups: [], throw_distance: [5, 7], gems_small: 10, gems_medium: 4, coins: [1, 5] },
  };
  const TYPES = ['brown', 'black'];
  const EVERY_MIN = 5;
  const FAR_BAND = 1.5;
  /** The map's barrels at the start (game/core/systems/BarrelField.gd COUNT, EXTRA_DARK, LIGHT_FRAC). */
  const START_COUNT = 35;

  const isObj = (x) => x != null && typeof x === 'object' && !Array.isArray(x);
  const num = (v, fb) => (typeof v === 'number' && isFinite(v) ? v : (typeof v === 'boolean' ? (v ? 1 : 0) : (typeof v === 'string' && v.trim() !== '' && isFinite(Number(v)) ? Number(v) : fb)));
  const bool = (v) => (typeof v === 'boolean' ? v : (typeof v === 'number' ? v !== 0 : (typeof v === 'string' ? ['true', '1', 'yes', 'on'].includes(v.toLowerCase()) : false)));
  const clamp = (x, a, b) => Math.min(Math.max(x, a), b);

  /** A number or [min, max] as [min, max]; `fb` for anything else (BarrelSpawns.range_of). */
  function rangeOf(v, fb) {
    if (typeof v === 'number' && isFinite(v)) return [v, v];
    if (Array.isArray(v) && v.length) { const a = num(v[0], fb[0]); const b = num(v[v.length - 1], a); return [Math.min(a, b), Math.max(a, b)]; }
    return fb.slice();
  }

  /** The respawn block whole (`barrels.respawn`), every key filled and in range, as the game reads it. */
  function respawnOf(block) {
    const own = isObj(block) && isObj(block.respawn) ? block.respawn : null;
    const has = !!own && Object.keys(own).length > 0;
    const o = Object.assign({}, RESPAWN_DEFAULTS, has ? own : {});
    o.enabled = has && bool(o.enabled);
    o.first = Math.max(num(o.first, 45), 0);
    const ev = rangeOf(o.every, [40, 60]);
    o.every = [Math.max(ev[0], EVERY_MIN), Math.max(ev[1], EVERY_MIN)];
    o.max_lying = Math.max(Math.trunc(num(o.max_lying, 35)), 0);
    o.max_per_stage = Math.max(Math.trunc(num(o.max_per_stage, 0)), 0);
    o.min_dist = Math.max(num(o.min_dist, 20), 0);
    o.max_dist = Math.max(num(o.max_dist, 40), o.min_dist);
    o.black_chance = clamp(num(o.black_chance, 0.22), 0, 1);
    o.view_margin = Math.max(num(o.view_margin, 2), 0);
    for (const k of ['in_boss', 'in_portal', 'in_endless']) o[k] = bool(o[k]);
    return o;
  }

  /** A power-up list as [{id, weight}] with every weight above 0 ([{id, weight}] or {id: weight}). */
  function weightList(v) {
    const out = [];
    if (isObj(v)) { for (const id of Object.keys(v)) if (id !== '' && num(v[id], 0) > 0) out.push({ id, weight: num(v[id], 0) }); }
    else if (Array.isArray(v)) {
      for (const r of v) {
        if (!isObj(r) || r.id == null || String(r.id) === '') continue;
        const w = num(r.weight, 1);
        if (w > 0) out.push({ id: String(r.id), weight: w });
      }
    }
    return out;
  }

  /** One barrel kind's contents, every key filled and in range (BarrelSpawns.contents_of; coins as [min, max]). */
  function contentsOf(block, type) {
    const own = isObj(block) && isObj(block[type]) ? block[type] : {};
    const o = Object.assign(JSON.parse(JSON.stringify(CONTENT_DEFAULTS[type])), own);
    o.powerup_chance = clamp(num(o.powerup_chance, 0), 0, 1);
    const td = rangeOf(o.throw_distance, [5, 7]);
    o.throw_distance = [Math.max(td[0], 0), Math.max(td[1], Math.max(td[0], 0))];
    o.gems_small = Math.max(Math.trunc(num(o.gems_small, 8)), 0);
    o.gems_medium = Math.max(Math.trunc(num(o.gems_medium, 0)), 0);
    const co = rangeOf(o.coins, [0, 0]);
    o.coins = [Math.max(Math.trunc(co[0]), 0), Math.max(Math.trunc(co[1]), Math.max(Math.trunc(co[0]), 0))];
    o.powerups = weightList(o.powerups);
    return o;
  }

  /** The list a barrel kind draws from: its own, else the map's power-up drops roster (`tl.pickups.roster`). */
  function drawList(tl, type) {
    const own = contentsOf(tl && tl.barrels, type).powerups;
    if (own.length) return { list: own, from: 'own' };
    return { list: weightList(((tl && tl.pickups) || {}).roster || []), from: 'drops' };
  }

  /** Each entry's share of the weights (0..1), in the list's order. */
  function shares(list) {
    const total = list.reduce((a, r) => a + Math.max(num(r.weight, 0), 0), 0);
    return list.map((r) => (total > 0 ? Math.max(num(r.weight, 0), 0) / total : 0));
  }

  /** How many turns of the respawn clock fall due in `length` seconds of it (BarrelSpawns.turns_in): the most barrels
   *  that many seconds can bring back (fewer when fewer were smashed: a turn with Most standing up is skipped). */
  function turnsIn(c, length) {
    if (!c.enabled || length < c.first) return 0;
    const mean = Math.max((c.every[0] + c.every[1]) / 2, EVERY_MIN);
    const n = 1 + Math.floor((length - c.first) / mean);
    return c.max_per_stage > 0 ? Math.min(n, c.max_per_stage) : n;
  }

  const okRange = (t) => (typeof t === 'number' && t >= 0) || (Array.isArray(t) && t.length === 2 && t.every((x) => typeof x === 'number' && x >= 0) && t[1] >= t[0]);

  /** The page's checks on the block: [{level: 'error'|'warn', msg}]. `pickupIds` the power-ups the game has (null: not
   *  checked). */
  function issues(tl, pickupIds) {
    const out = [];
    const err = (msg) => out.push({ level: 'error', msg });
    const warn = (msg) => out.push({ level: 'warn', msg });
    const b = tl ? tl.barrels : undefined;
    if (b == null) return out;
    if (!isObj(b)) { err('barrels must be a block {respawn, brown, black}'); return out; }
    for (const k of Object.keys(b)) if (!['respawn', ...TYPES].includes(k)) warn(`"${k}" is not respawn, brown or black: the game ignores it`);
    const rs = b.respawn;
    if (rs != null && !isObj(rs)) err('respawn must be a block {enabled, first, every, ...}');
    else if (isObj(rs)) {
      for (const k of ['first', 'max_lying', 'max_per_stage', 'min_dist', 'max_dist', 'view_margin']) {
        if (rs[k] != null && !(typeof rs[k] === 'number' && rs[k] >= 0)) err(`respawn: ${k} must be a number 0 or more (got ${JSON.stringify(rs[k])})`);
      }
      if (rs.every != null && !okRange(rs.every)) err('respawn: every is seconds, one number or [min, max] with max at least min');
      if (rs.black_chance != null && !(typeof rs.black_chance === 'number' && rs.black_chance >= 0 && rs.black_chance <= 1)) err('respawn: the black barrel chance is between 0 and 100%');
      const c = respawnOf(b);
      if (c.enabled) {
        if (c.every[0] < 10) warn(`respawn: a barrel back every ${c.every[0]} s is a lot of free XP`);
        if (c.max_dist < 12) warn(`respawn: within ${c.max_dist} m most spots are on the screen; the game will often look farther`);
        if (c.max_lying === 0) warn('respawn: no limit on barrels standing: the map fills up over a stage');
        else if (c.max_lying > 80) warn(`respawn: up to ${c.max_lying} barrels standing is far more than the start's ${START_COUNT}`);
      }
    }
    for (const ty of TYPES) {
      const k = b[ty];
      if (k == null) continue;
      const name = ty === 'black' ? 'black barrel' : 'brown barrel';
      if (!isObj(k)) { err(`${name}: must be a block`); continue; }
      if (k.powerup_chance != null && !(typeof k.powerup_chance === 'number' && k.powerup_chance >= 0 && k.powerup_chance <= 1)) err(`${name}: the power-up chance is between 0 and 100%`);
      if (k.powerups != null && !Array.isArray(k.powerups) && !isObj(k.powerups)) err(`${name}: powerups must be a list of {id, weight}`);
      if (Array.isArray(k.powerups)) {
        k.powerups.forEach((r, n) => {
          if (!isObj(r) || !r.id) err(`${name}: power-up ${n + 1} has no id`);
          else if (pickupIds && !pickupIds.includes(String(r.id))) err(`${name}: unknown power-up "${r.id}"`);
          if (isObj(r) && r.weight != null && !(typeof r.weight === 'number' && r.weight >= 0)) err(`${name}: power-up ${n + 1}'s weight must be 0 or more`);
        });
        if (k.powerups.length && !weightList(k.powerups).length) warn(`${name}: every power-up weighs 0: the drops roster is used instead`);
      }
      if (k.throw_distance != null) {
        if (!okRange(k.throw_distance)) err(`${name}: throw distance is metres, one number or [min, max] with max at least min`);
        else if (rangeOf(k.throw_distance, [5, 7])[0] < 2) warn(`${name}: a power-up thrown under 2 m lands at the hero's feet (he stands at the barrel) and is taken at once`);
      }
      for (const f of ['gems_small', 'gems_medium']) if (k[f] != null && !(Number.isInteger(k[f]) && k[f] >= 0)) err(`${name}: ${f} must be a whole number 0 or more`);
      if (k.coins != null && !okRange(k.coins)) err(`${name}: coins are one number or [min, max] with max at least min`);
      const con = contentsOf(b, ty);
      if (con.powerup_chance > 0 && !con.powerups.length && !weightList(((tl && tl.pickups) || {}).roster || []).length) warn(`${name}: a power-up chance but no power-up listed and no drops roster: nothing comes out`);
      if (con.powerup_chance > 0.5) warn(`${name}: a power-up from over half of them makes power-ups common (the crowd drops about 17 a Sundown run)`);
    }
    return out;
  }

  const api = { RESPAWN_DEFAULTS, CONTENT_DEFAULTS, TYPES, EVERY_MIN, FAR_BAND, START_COUNT, rangeOf, respawnOf, weightList, contentsOf, drawList, shares, turnsIn, issues };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  return api;
})();
