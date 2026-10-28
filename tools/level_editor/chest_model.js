'use strict';
// Pass 111 (lane CHEST): the page-free maths of the map's chests, a copy of game/core/systems/WorldChests.gd's tables and
// rules (DEFAULTS, CONTENT_DEFAULTS, cfg_of, contents_of, weight_list, expected_in) for the Settings tab's Chests card
// (chest_card.js) and the page's checks. selftest_CHEST111.py runs it under Node and checks its tables against the
// GDScript's. Two blocks of timeline_data: `world_chests` (the map's own chests, laid off the screen on a clock) and
// `chest_contents` {normal, boss} (a power-up's chance out of each chest type, which one, how far it is thrown, the
// reel's new-item weight and gold, the boss chest's mutation).
const ChestModel = (() => {
  const DEFAULTS = {
    enabled: false, first: 60, every: [90, 130], max_on_map: 2, max_per_stage: 0,
    min_dist: 25, max_dist: 45, boss_chance: 0, lifetime: 150, view_margin: 3,
    in_boss: true, in_portal: false, in_endless: false, pointer: true,
  };
  const CONTENT_DEFAULTS = {
    normal: { powerup_chance: 0, powerups: [], throw_distance: [5, 7], new_item_weight: 0.45, gold: 50 },
    boss: { powerup_chance: 0, powerups: [], throw_distance: [5, 7], new_item_weight: 0.45, gold: 50, mutation: true },
  };
  const TYPES = ['normal', 'boss'];
  const EVERY_MIN = 5;
  const FAR_BAND = 1.5;

  const isObj = (x) => x != null && typeof x === 'object' && !Array.isArray(x);
  const num = (v, fb) => (typeof v === 'number' && isFinite(v) ? v : (typeof v === 'boolean' ? (v ? 1 : 0) : (typeof v === 'string' && v.trim() !== '' && isFinite(Number(v)) ? Number(v) : fb)));
  const bool = (v) => (typeof v === 'boolean' ? v : (typeof v === 'number' ? v !== 0 : (typeof v === 'string' ? ['true', '1', 'yes', 'on'].includes(v.toLowerCase()) : false)));
  const clamp = (x, a, b) => Math.min(Math.max(x, a), b);

  /** A number or [min, max] as [min, max]; `fb` for anything else (WorldChests.range_of). */
  function rangeOf(v, fb) {
    if (typeof v === 'number' && isFinite(v)) return [v, v];
    if (Array.isArray(v) && v.length) { const a = num(v[0], fb[0]); const b = num(v[v.length - 1], a); return [Math.min(a, b), Math.max(a, b)]; }
    return fb.slice();
  }

  /** The world chests' block whole, every key filled and in range, as the game reads it (WorldChests.cfg_of). */
  function cfgOf(block) {
    const has = isObj(block) && Object.keys(block).length > 0;
    const o = Object.assign({}, DEFAULTS, has ? block : {});
    o.enabled = has && bool(o.enabled);
    o.first = Math.max(num(o.first, 60), 0);
    const ev = rangeOf(o.every, [90, 130]);
    o.every = [Math.max(ev[0], EVERY_MIN), Math.max(ev[1], EVERY_MIN)];
    o.max_on_map = Math.max(Math.trunc(num(o.max_on_map, 2)), 0);
    o.max_per_stage = Math.max(Math.trunc(num(o.max_per_stage, 0)), 0);
    o.min_dist = Math.max(num(o.min_dist, 25), 0);
    o.max_dist = Math.max(num(o.max_dist, 45), o.min_dist);
    o.boss_chance = clamp(num(o.boss_chance, 0), 0, 1);
    o.lifetime = Math.max(num(o.lifetime, 150), 0);
    o.view_margin = Math.max(num(o.view_margin, 3), 0);
    for (const k of ['in_boss', 'in_portal', 'in_endless', 'pointer']) o[k] = bool(o[k]);
    return o;
  }

  /** A power-up list as [{id, weight}] with every weight above 0 ([{id, weight}] or {id: weight}; WorldChests.weight_list). */
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

  /** One chest type's contents, every key filled and in range (WorldChests.contents_of). */
  function contentsOf(block, type) {
    const own = isObj(block) && isObj(block[type]) ? block[type] : {};
    const o = Object.assign(JSON.parse(JSON.stringify(CONTENT_DEFAULTS[type])), own);
    o.powerup_chance = clamp(num(o.powerup_chance, 0), 0, 1);
    const td = rangeOf(o.throw_distance, [5, 7]);
    o.throw_distance = [Math.max(td[0], 0), Math.max(td[1], Math.max(td[0], 0))];
    o.new_item_weight = Math.max(num(o.new_item_weight, 0.45), 0);
    o.gold = Math.max(Math.trunc(num(o.gold, 50)), 0);
    if ('mutation' in o) o.mutation = bool(o.mutation);
    o.powerups = weightList(o.powerups);
    return o;
  }

  /** The list a chest type draws from: its own, else the map's power-up drops roster (`tl.pickups.roster`). */
  function drawList(tl, type) {
    const own = contentsOf(tl && tl.chest_contents, type).powerups;
    if (own.length) return { list: own, from: 'own' };
    return { list: weightList(((tl && tl.pickups) || {}).roster || []), from: 'drops' };
  }

  /** Each entry's share of the weights (0..1), in the list's order. */
  function shares(list) {
    const total = list.reduce((a, r) => a + Math.max(num(r.weight, 0), 0), 0);
    return list.map((r) => (total > 0 ? Math.max(num(r.weight, 0), 0) / total : 0));
  }

  /** About how many world chests a stage of `length` seconds lays when every turn finds room (WorldChests.expected_in):
   *  the first at `first`, then one every `every` on average, at most max_per_stage. */
  function expectedIn(c, length) {
    if (!c.enabled || length < c.first) return 0;
    const mean = Math.max((c.every[0] + c.every[1]) / 2, EVERY_MIN);
    const n = 1 + Math.floor((length - c.first) / mean);
    return c.max_per_stage > 0 ? Math.min(n, c.max_per_stage) : n;
  }

  /** The page's checks on both blocks: [{level: 'error'|'warn', msg}]. `pickupIds` the power-ups the game has (null: not
   *  checked). */
  function issues(tl, pickupIds) {
    const out = [];
    const err = (msg) => out.push({ level: 'error', msg });
    const warn = (msg) => out.push({ level: 'warn', msg });
    const wc = tl ? tl.world_chests : undefined;
    if (wc != null && !isObj(wc)) err('world_chests must be a block {enabled, first, every, ...}');
    else if (isObj(wc)) {
      for (const k of ['first', 'max_on_map', 'max_per_stage', 'min_dist', 'max_dist', 'lifetime', 'view_margin']) {
        if (wc[k] != null && !(typeof wc[k] === 'number' && wc[k] >= 0)) err(`map chests: ${k} must be a number 0 or more (got ${JSON.stringify(wc[k])})`);
      }
      if (wc.every != null) {
        const ok = (typeof wc.every === 'number' && wc.every >= 0) || (Array.isArray(wc.every) && wc.every.length === 2 && wc.every.every((x) => typeof x === 'number' && x >= 0) && wc.every[1] >= wc.every[0]);
        if (!ok) err('map chests: every is seconds, one number or [min, max] with max at least min');
      }
      if (wc.boss_chance != null && !(typeof wc.boss_chance === 'number' && wc.boss_chance >= 0 && wc.boss_chance <= 1)) err('map chests: the boss chest chance is between 0 and 100%');
      const c = cfgOf(wc);
      if (c.enabled) {
        if (c.every[0] < 20) warn(`map chests: one every ${c.every[0]} s is a lot of chests (each one is a level-up's worth)`);
        if (c.max_dist < 15) warn(`map chests: within ${c.max_dist} m most spots are on the screen; the game will often look farther`);
        if (c.lifetime > 0 && c.lifetime < 30) warn(`map chests: ${c.lifetime} s is little time to reach one ${c.min_dist}-${c.max_dist} m away`);
        if (c.max_on_map === 0 && c.lifetime === 0) warn('map chests: no limit on how many lie and they never go: unopened ones pile up over a stage');
      }
    }
    const cc = tl ? tl.chest_contents : undefined;
    if (cc != null && !isObj(cc)) err('chest_contents must be a block {normal: {...}, boss: {...}}');
    else if (isObj(cc)) {
      for (const k of Object.keys(cc)) if (!TYPES.includes(k)) warn(`chest contents: "${k}" is not a chest type (normal or boss): the game ignores it`);
      for (const ty of TYPES) {
        const b = cc[ty];
        if (b == null) continue;
        const name = ty === 'boss' ? 'boss chest' : 'normal chest';
        if (!isObj(b)) { err(`${name}: must be a block`); continue; }
        if (b.powerup_chance != null && !(typeof b.powerup_chance === 'number' && b.powerup_chance >= 0 && b.powerup_chance <= 1)) err(`${name}: the power-up chance is between 0 and 100%`);
        if (b.powerups != null && !Array.isArray(b.powerups) && !isObj(b.powerups)) err(`${name}: powerups must be a list of {id, weight}`);
        if (Array.isArray(b.powerups)) {
          b.powerups.forEach((r, k) => {
            if (!isObj(r) || !r.id) err(`${name}: power-up ${k + 1} has no id`);
            else if (pickupIds && !pickupIds.includes(String(r.id))) err(`${name}: unknown power-up "${r.id}"`);
            if (isObj(r) && r.weight != null && !(typeof r.weight === 'number' && r.weight >= 0)) err(`${name}: power-up ${k + 1}'s weight must be 0 or more`);
          });
          if (b.powerups.length && !weightList(b.powerups).length) warn(`${name}: every power-up weighs 0: the drops roster is used instead`);
        }
        if (b.throw_distance != null) {
          const t = b.throw_distance;
          const ok = (typeof t === 'number' && t >= 0) || (Array.isArray(t) && t.length === 2 && t.every((x) => typeof x === 'number' && x >= 0) && t[1] >= t[0]);
          if (!ok) err(`${name}: throw distance is metres, one number or [min, max] with max at least min`);
          else if (rangeOf(t, [5, 7])[0] < 2) warn(`${name}: a power-up thrown under 2 m lands at the hero's feet (he stands at the chest) and is taken at once`);
        }
        for (const k of ['new_item_weight', 'gold']) if (b[k] != null && !(typeof b[k] === 'number' && b[k] >= 0)) err(`${name}: ${k} must be a number 0 or more`);
        if (b.mutation != null && typeof b.mutation !== 'boolean') err(`${name}: mutation is on or off (true / false)`);
        const con = contentsOf(cc, ty);
        if (con.powerup_chance > 0 && !con.powerups.length && !weightList(((tl && tl.pickups) || {}).roster || []).length) warn(`${name}: a power-up chance but no power-up listed and no drops roster: nothing comes out`);
      }
    }
    return out;
  }

  const api = { DEFAULTS, CONTENT_DEFAULTS, TYPES, EVERY_MIN, FAR_BAND, rangeOf, cfgOf, weightList, contentsOf, drawList, shares, expectedIn, issues };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  return api;
})();
