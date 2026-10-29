'use strict';
// Pass 111, lane WANTED: the Bounty Board's page-free maths (the Wanted tab, wanted.js; run under Node by
// selftest_WANTED111.py). It mirrors game/core/systems/WantedBoard.gd's pure part line for line: the types, the targets a
// run may have, the draw by weight without putting back, the exact chances, the number ranges grown with progression,
// the difficulty from where a number fell, the reward, the texts. The context it rolls from is built by contextFrom()
// out of what the editor already has (the map's timeline, the creatures, the items, the heroes), with the save's facts
// (met, seen, unlocked) assumed by the page's switches. Rules: BALANCING.md 54.WANTED.
const WantedModel = (() => {
  const TYPES = {
    kill_enemy: { target: 'enemy', param: true, down: false },
    kill_weapon: { target: 'weapon', param: true, down: false },
    kill_specials: { target: '', param: true, down: false },
    kill_elites: { target: '', param: true, down: false },
    kill_total: { target: '', param: true, down: false },
    boss_fast: { target: 'boss', param: true, down: true },
    hp_floor: { target: 'boss', param: true, down: false },
    beat_stage: { target: '', param: false, down: false },
    hero_level: { target: '', param: true, down: false },
    max_weapon: { target: 'weapon', param: false, down: false },
    evolve_item: { target: 'evolve', param: false, down: false },
    open_chests: { target: '', param: true, down: false },
    collect_coins: { target: '', param: true, down: false },
    // pass 113 (lane TASKS): BALANCING 56.TASKS
    damage_weapon: { target: 'weapon', param: true, down: false },
    heal_item: { target: 'item', param: true, down: false },
    heal_source: { target: 'source', param: true, down: false },
    item_level: { target: 'item', param: false, down: false },
    barrels: { target: '', param: true, down: false },
    totems: { target: '', param: true, down: false },
    element_damage: { target: 'element', param: true, down: false },
  };
  const TYPE_ORDER = ['kill_enemy', 'kill_weapon', 'kill_specials', 'kill_elites', 'kill_total', 'boss_fast', 'hp_floor',
    'beat_stage', 'hero_level', 'max_weapon', 'evolve_item', 'open_chests', 'collect_coins', 'damage_weapon', 'heal_item',
    'heal_source', 'item_level', 'barrels', 'totems', 'element_damage'];
  // pass 113: the types whose number is rolled once the target is drawn (its `target_mult` factor scales the range)
  const TARGET_FIRST = ['damage_weapon', 'heal_item', 'heal_source', 'element_damage'];
  const ELEMENT_NAMES = { fire: 'Fire', poison: 'Poison' };
  // TaskTally.HEAL_STATS / ELEMENTS; PassiveDef.LADDER
  const HEAL_STATS = ['lifesteal', 'regen', 'still_regen', 'crit_heal_chance', 'heal_drop'];
  const ELEMENTS = ['fire', 'poison'];
  const LADDER = ['common', 'uncommon', 'rare', 'epic', 'legendary'];
  // what each type is, in Garry's words (the tab's cards), and what its extras mean
  const TYPE_INFO = {
    kill_enemy: { label: 'Kill N of a creature', help: 'a creature on this stage\'s roster for at least Min seconds (met before, when "creatures met only"), drawn by its seconds on the roster; never more than Cap a minute of those seconds; its front still on the poster' },
    kill_weapon: { label: 'Kill N with a weapon', help: 'a weapon this hero may find (unlocked, not hidden, open on this stage; seen before, when "items seen only") or his own; his own is Start weight times as likely; another one adds Other bonus to the difficulty; its icon on the poster' },
    kill_specials: { label: 'Kill N specials', help: 'the glowing specials and the geared ones (the Rocketeer, the Saiga Sniper...); a geared creature met on this stage on the poster' },
    kill_elites: { label: 'Kill N Elites', help: 'Elites (crowned, or wearing an Elite modifier); never more than the stage brings (its Elite events and Elite rows); offered only when it brings one' },
    kill_total: { label: 'Kill N creatures', help: 'every kill of the run; the stage\'s picture on the poster' },
    boss_fast: { label: 'Beat the boss within T seconds', help: 'from his arrival to his death; a LOWER number is harder (progression shortens it); the boss met before only; his still on the poster' },
    hp_floor: { label: 'Beat the boss, never under P% HP', help: 'the hero\'s health never under P% of his max until the boss dies (a revive counts as falling under); Max caps it; the hero on the poster' },
    beat_stage: { label: 'Beat the stage as the hero', help: 'no number: difficulty is its first value when the stage was beaten before, its second when never' },
    hero_level: { label: 'Reach hero level L', help: 'the hero\'s level in this run; the hero on the poster' },
    max_weapon: { label: 'Get a weapon to its top level', help: 'no number (its top level); the first difficulty value, plus Other bonus for a weapon that is not his own' },
    evolve_item: { label: 'Evolve an item', help: 'his own weapon (when it evolves) or a card that evolves; difficulty: first value for a card, second for his weapon; Start weight = how likely his weapon is against one card' },
    open_chests: { label: 'Open N chests', help: 'chests opened or skipped in this run; the chest on the poster' },
    collect_coins: { label: 'Collect N gold', help: 'gold picked up in the run (after greed); the coin on the poster' },
    // pass 113 (lane TASKS)
    damage_weapon: { label: 'Deal N damage with a weapon', help: 'the damage the weapon and its evolution deal in the run (what the creature still had in it, never overkill); targets as Kill N with a weapon (his own Start weight times as likely, another one adds Other bonus); a weapon\'s own factor below scales its range; its icon on the poster' },
    heal_item: { label: 'Restore N HP with an item', help: 'HP the item gives back in the run: life steal (Death), regen (Temperance, Hot Springs), Siesta\'s stand-still regen, Vulture\'s crit heal, Cake\'s slices (its share when two items heal the same way); a card or passive item that heals, unlocked and seen; each item\'s own factor below sizes its range (a Cake heals far less than Death); its icon on the poster' },
    heal_source: { label: 'Restore N HP with a power-up or structure', help: 'HP the Heart or the Healing Well gives back in the run; only a healing power-up this map drops (kills or barrels) or a healing structure it places; a source\'s own factor below; its icon on the poster' },
    item_level: { label: 'Get an item to level N', help: 'a weapon (his own or one seen), a card or a passive item (seen) to level N, N rolled between Min level and that item\'s own top level (a passive item\'s ladder: common 6 .. epic 3); difficulty from where N fell (the top level = the hard end); its icon on the poster' },
    barrels: { label: 'Break N barrels', help: 'barrels the hero breaks in the run (brown and black); 35 stand at the start and broken ones come back now and then; Max caps the number; the barrel on the poster' },
    totems: { label: 'Take N Totem gifts', help: 'gifts taken at the Totem Poles in the run (a pole left without a gift does not count); never more than the map\'s poles (10-12); the Totem Pole on the poster' },
    element_damage: { label: 'Deal N fire or poison damage', help: 'burns (fire) or poison ticks the hero\'s side deals in the run; offered for an element an item this hero may find carries (a weapon\'s path mutations too); an element\'s own factor below; fire or the poison flask on the poster' },
  };
  const DEFAULTS = {
    enabled: true, choices: 3, rerolls: 0, unlock: { runs: 1 }, creatures_met_only: true, items_seen_only: true,
    progress: { param_growth: 0.15 }, reward: { base: 40, per_point: 60, progress_growth: 0.5, stage_mult: [1.0, 1.25, 1.5], round: 5, currency: 'gold' },
    tasks: [],
  };
  const MAX_CHOICES = 3;

  const isObj = (x) => x && typeof x === 'object' && !Array.isArray(x);
  const clone = (x) => JSON.parse(JSON.stringify(x));
  const num = (v, d) => (typeof v === 'number' && isFinite(v) ? v : (typeof v === 'string' && v.trim() !== '' && isFinite(Number(v)) ? Number(v) : d));
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const snapped = (v, step) => Math.round(v / step) * step;
  const round1 = (v) => Math.round(v * 10) / 10;

  function normalized(d) {
    const out = clone(DEFAULTS);
    for (const k of Object.keys(d || {})) {
      if (isObj(out[k]) && isObj(d[k])) Object.assign(out[k], clone(d[k]));
      else out[k] = clone(d[k]);
    }
    if (!Array.isArray(out.tasks)) out.tasks = [];
    return out;
  }

  function taskCfg(cfg, type) { return (cfg.tasks || []).find((t) => isObj(t) && String(t.type || '') === type) || {}; }

  function union(spans) {
    const s = spans.slice().sort((a, b) => a[0] - b[0]);
    let total = 0, a0 = -Infinity, b0 = -Infinity;
    for (const [a, b] of s) {
      if (a > b0) { if (b0 > a0) total += b0 - a0; a0 = a; b0 = b; } else b0 = Math.max(b0, b);
    }
    if (b0 > a0) total += b0 - a0;
    return total;
  }

  function targetsOf(cfg, type, ctx) {
    const tc = taskCfg(cfg, type);
    const metOnly = cfg.creatures_met_only !== false;
    const seenOnly = cfg.items_seen_only !== false;
    switch (type) {
      case 'kill_enemy': {
        const minS = num(tc.min_seconds, 40);
        return (ctx.creatures || []).filter((c) => !c.elite && num(c.seconds, 0) >= minS && (c.met || !metOnly));
      }
      case 'kill_weapon': case 'max_weapon':
        return (ctx.weapons || []).filter((w) => w.start || w.seen || !seenOnly);
      case 'evolve_item': {
        const out = [];
        for (const w of ctx.weapons || []) if (w.start && w.evolves) out.push(Object.assign({}, w, { kind: 'weapon' }));
        for (const c of ctx.cards || []) if (c.evolves && (c.seen || !seenOnly)) out.push(Object.assign({}, c, { kind: 'card' }));
        return out;
      }
      case 'boss_fast': case 'hp_floor': {
        const b = ctx.boss || {};
        return b.id && (b.met || !metOnly) ? [b] : [];
      }
      case 'kill_elites': return num(ctx.elite_estimate, 0) >= 1 ? [{ id: '' }] : [];
      case 'beat_stage': return (ctx.boss || {}).id ? [{ id: '' }] : [];
      // pass 113 (lane TASKS)
      case 'damage_weapon': return (ctx.weapons || []).filter((w) => w.start || w.seen || !seenOnly);
      case 'heal_item': return (ctx.heal_items || []).filter((x) => x.seen || !seenOnly);
      case 'heal_source': return (ctx.heal_sources || []).slice();
      case 'item_level': {
        const minLv = Math.max(Math.round(num(tc.min_level, 2)), 1);
        const out = [];
        for (const w of ctx.weapons || []) if ((w.start || w.seen || !seenOnly) && num(w.max_level, 1) >= minLv) out.push(Object.assign({}, w, { kind: 'weapon' }));
        for (const key of ['cards', 'passive_items']) {
          for (const x of ctx[key] || []) if ((x.seen || !seenOnly) && num(x.max_level, 1) >= minLv) out.push(Object.assign({}, x, { kind: key === 'cards' ? 'card' : 'passive' }));
        }
        return out;
      }
      case 'totems': return num(ctx.totem_poles, 0) >= 1 ? [{ id: 'totem_pole' }] : [];
      case 'element_damage': return (ctx.elements || []).slice();
    }
    return [{ id: '' }];
  }

  function eligibleTypes(cfg, ctx) {
    const out = [];
    for (const type of TYPE_ORDER) {
      const tc = taskCfg(cfg, type);
      if (!Object.keys(tc).length || tc.on === false) continue;
      const w = num(tc.weight, 0);
      if (w <= 0 || !targetsOf(cfg, type, ctx).length) continue;
      out.push({ type, weight: w });
    }
    return out;
  }

  function choicesOf(cfg) { return clamp(Math.round(num(cfg.choices, 3)), 1, MAX_CHOICES); }

  /** {type: {first, board}}: the share of the weight, and the exact chance to be one of the posters. */
  function typeChances(cfg, ctx) {
    const el = eligibleTypes(cfg, ctx);
    const total = el.reduce((a, e) => a + e.weight, 0);
    const out = {};
    for (const e of el) out[e.type] = { first: total > 0 ? e.weight / total : 0, board: 0 };
    const walk = (pool, left, p) => {
      if (left <= 0 || !pool.length) return;
      const t = pool.reduce((a, e) => a + e.weight, 0);
      if (t <= 0) return;
      pool.forEach((e, i) => {
        const pi = p * e.weight / t;
        out[e.type].board += pi;
        walk(pool.filter((_, j) => j !== i), left - 1, pi);
      });
    };
    walk(el, choicesOf(cfg), 1);
    return out;
  }

  function scaledRange(cfg, type, tc, stage, p) {
    const ns = Array.isArray(tc.n) ? tc.n : [];
    if (!ns.length) return [0, 0];
    const e = ns[clamp(stage, 0, ns.length - 1)];
    let lo = 0, hi = 0;
    if (Array.isArray(e) && e.length >= 2) { lo = num(e[0], 0); hi = num(e[1], 0); } else if (typeof e === 'number') { lo = e; hi = e; }
    if (hi < lo) [lo, hi] = [hi, lo];
    const growth = num(tc.growth, num((cfg.progress || {}).param_growth, 0.15));
    const f = Math.max(1 + growth * Math.max(p, 0), 0.05);
    if ((TYPES[type] || {}).down) { lo /= f; hi /= f; } else { lo *= f; hi *= f; }
    if (tc.max != null && isFinite(Number(tc.max))) { lo = Math.min(lo, Number(tc.max)); hi = Math.min(hi, Number(tc.max)); }
    return [lo, hi];
  }

  /** Pass 113: range `r` for target `id`, times the type's `target_mult` factor for it (1 without one). */
  function targetRange(tc, r, id) {
    const tm = isObj(tc.target_mult) ? tc.target_mult : null;
    if (!tm || !(id in tm)) return r;
    const f = Math.max(num(tm[id], 0), 0);
    return [r[0] * f, r[1] * f];
  }
  const plural = (s) => s + (/[sx]$/.test(s) ? 'es' : 's');

  function snapN(v, step) { const s = Math.max(num(step, 1), 1); return Math.max(Math.round(v / s) * s, s); }
  function rollN(r, step, rnd) { return snapN(r[0] + (r[1] - r[0]) * rnd(), step); }

  function difficultyOf(lo, hi, n, r, down) {
    let t = 0.5;
    if (r[1] - r[0] > 0.0001) { t = clamp((n - r[0]) / (r[1] - r[0]), 0, 1); if (down) t = 1 - t; }
    return round1(lo + (hi - lo) * t);
  }
  function skullsOf(d) { return clamp(Math.round(d), 1, 5); }

  function rewardFor(cfg, d, p, stage) {
    const rw = cfg.reward || {};
    const sm = Array.isArray(rw.stage_mult) && rw.stage_mult.length ? rw.stage_mult : [1];
    const smult = num(sm[clamp(stage, 0, sm.length - 1)], 1);
    const raw = (num(rw.base, 40) + num(rw.per_point, 60) * d) * (1 + num(rw.progress_growth, 0.5) * Math.max(p, 0)) * smult;
    const step = Math.max(num(rw.round, 5), 1);
    return Math.max(Math.round(raw / step) * step, step);
  }

  function pick(list, weightOf, rnd) {
    if (!list.length) return {};
    const total = list.reduce((a, x) => a + Math.max(num(weightOf(x), 0), 0), 0);
    if (total <= 0) return list[0];
    let r = rnd() * total;
    for (const x of list) { r -= Math.max(num(weightOf(x), 0), 0); if (r < 0) return x; }
    return list[list.length - 1];
  }

  function fillText(tpl, vars) { let s = String(tpl || ''); for (const k of Object.keys(vars)) s = s.split('{' + k + '}').join(String(vars[k])); return s; }
  function clockOf(sec) { const t = Math.round(Math.max(sec, 0)); return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`; }
  function numText(n) { return n >= 1000 ? n.toLocaleString('en-US') : String(n); }
  const firstMet = (list) => (list || []).find((x) => x && x.met) || null;

  function makeContract(cfg, type, ctx, rnd) {
    const tc = taskCfg(cfg, type);
    const cands = targetsOf(cfg, type, ctx);
    if (!Object.keys(tc).length || !cands.length) return null;
    const k = num(ctx.stage, 0), p = num(ctx.P, 0);
    const hero = ctx.hero || {}, boss = ctx.boss || {};
    const dif = Array.isArray(tc.difficulty) ? tc.difficulty : [1, 3];
    const lo = num(dif[0], 1), hi = dif.length > 1 ? num(dif[1], lo) : lo;
    const down = !!(TYPES[type] || {}).down;
    const step = num(tc.step, 1);
    const r = scaledRange(cfg, type, tc, k, p);
    const c = { type, target: '', target_kind: '', n: 0, stage: k, map: ctx.map || '', hero: hero.id || '', P: p, still: {} };
    const vars = { hero: hero.name || '', stage: ctx.stage_name || '', boss: boss.name || '', target: '' };
    let d = lo, n = 0;
    if ((TYPES[type] || {}).param && !TARGET_FIRST.includes(type)) n = rollN(r, step, rnd);
    switch (type) {
      case 'kill_enemy': {
        const cr = pick(cands, (x) => num(x.seconds, 0), rnd);
        const cap = snapN(num(tc.per_minute_cap, 30) * num(cr.seconds, 0) / 60 - Math.max(step, 1) * 0.49, step);
        n = Math.min(n, cap);
        d = difficultyOf(lo, hi, n, r, down);
        Object.assign(c, { target: cr.id, target_kind: 'enemy', still: { kind: 'enemy', id: cr.id } });
        vars.target = cr.name || cr.id;
        break;
      }
      case 'kill_weapon': case 'max_weapon': {
        const sw = num(tc.start_weight, 3);
        const wp = pick(cands, (x) => (x.start ? sw : 1), rnd);
        const bonus = wp.start ? 0 : num(tc.other_bonus, 1);
        if (type === 'max_weapon') { n = num(wp.max_level, 5); d = round1(lo + bonus); } else d = round1(difficultyOf(lo, hi, n, r, down) + bonus);
        Object.assign(c, { target: wp.id, target_kind: 'weapon', still: { kind: 'weapon', id: wp.id } });
        vars.target = wp.name || wp.id;
        break;
      }
      case 'evolve_item': {
        const sw = num(tc.start_weight, 1);
        const it = pick(cands, (x) => (x.kind === 'weapon' ? sw : 1), rnd);
        const isW = it.kind === 'weapon';
        d = round1(isW ? hi : lo); n = 1;
        Object.assign(c, { target: it.id, target_kind: isW ? 'weapon' : 'card', still: { kind: isW ? 'weapon' : 'card', id: it.id } });
        vars.target = it.name || it.id;
        break;
      }
      case 'kill_specials': {
        d = difficultyOf(lo, hi, n, r, down);
        const g = firstMet(ctx.gear) || firstMet((ctx.creatures || []).filter((x) => x.special));
        c.still = g ? { kind: 'enemy', id: g.id, badge: 'gear' } : { kind: 'badge', id: 'gear' };
        break;
      }
      case 'kill_elites': {
        n = Math.min(n, Math.max(num(ctx.elite_estimate, 1), 1));
        d = difficultyOf(lo, hi, n, r, down);
        const e = firstMet(ctx.elite_boss);
        c.still = e ? { kind: 'enemy', id: e.id, badge: 'crown' } : { kind: 'badge', id: 'crown' };
        break;
      }
      case 'kill_total': d = difficultyOf(lo, hi, n, r, down); c.still = { kind: 'stage', id: ctx.map || '', stage: k, badge: 'skull' }; break;
      case 'boss_fast':
        d = difficultyOf(lo, hi, n, r, down);
        Object.assign(c, { target: boss.id || '', target_kind: 'boss', still: { kind: 'enemy', id: boss.id || '', badge: 'skull' } });
        vars.time = clockOf(n);
        break;
      case 'hp_floor':
        d = difficultyOf(lo, hi, n, r, down);
        Object.assign(c, { target: boss.id || '', target_kind: 'boss', still: { kind: 'hero', id: hero.id || '', badge: 'heart' } });
        break;
      case 'beat_stage': d = round1(ctx.beaten ? lo : hi); n = 1; c.still = { kind: 'stage', id: ctx.map || '', stage: k }; break;
      case 'hero_level': d = difficultyOf(lo, hi, n, r, down); c.still = { kind: 'hero', id: hero.id || '' }; break;
      case 'open_chests': d = difficultyOf(lo, hi, n, r, down); c.still = { kind: 'art', id: 'chest' }; break;
      case 'collect_coins': d = difficultyOf(lo, hi, n, r, down); c.still = { kind: 'art', id: 'coin' }; break;
      // pass 113 (lane TASKS): WantedBoard.make_contract's new branches, draw for draw
      case 'damage_weapon': {
        const sw = num(tc.start_weight, 3);
        const wp = pick(cands, (x) => (x.start ? sw : 1), rnd);
        const r3 = targetRange(tc, r, wp.id);
        n = rollN(r3, step, rnd);
        const bonus = wp.start ? 0 : num(tc.other_bonus, 1);
        d = round1(difficultyOf(lo, hi, n, r3, down) + bonus);
        Object.assign(c, { target: wp.id, target_kind: 'weapon', still: { kind: 'weapon', id: wp.id } });
        vars.target = wp.name || wp.id;
        break;
      }
      case 'heal_item': case 'heal_source': case 'element_damage': {
        const it = pick(cands, () => 1, rnd);
        const id = String(it.id || '');
        const r4 = targetRange(tc, r, id);
        n = rollN(r4, step, rnd);
        d = difficultyOf(lo, hi, n, r4, down);
        c.target = id;
        vars.target = it.name || id;
        if (type === 'heal_item') { c.target_kind = it.kind || 'passive'; c.still = { kind: c.target_kind, id }; }
        else if (type === 'heal_source') { c.target_kind = it.kind || 'pickup'; vars.targets = plural(String(it.name || id)); c.still = { kind: c.target_kind, id }; }
        else { c.target_kind = 'element'; vars.element = id; c.still = { kind: 'art', id }; }
        break;
      }
      case 'item_level': {
        const sw = num(tc.start_weight, 1);
        const it = pick(cands, (x) => (x.start ? sw : 1), rnd);
        const top = Math.max(Math.round(num(it.max_level, 1)), 1);
        const low = clamp(Math.round(num(tc.min_level, 2)), 1, top);
        n = Math.min(low + Math.floor(rnd() * (top - low + 1)), top);
        d = difficultyOf(lo, hi, n, [low, top], false);
        Object.assign(c, { target: it.id, target_kind: it.kind || 'weapon', still: { kind: it.kind || 'weapon', id: it.id } });
        vars.target = it.name || it.id;
        break;
      }
      case 'barrels': d = difficultyOf(lo, hi, n, r, down); c.still = { kind: 'art', id: 'barrel' }; break;
      case 'totems':
        n = Math.min(n, Math.max(num(ctx.totem_poles, 1), 1));
        d = difficultyOf(lo, hi, n, r, down);
        Object.assign(c, { target: 'totem_pole', target_kind: 'structure', still: { kind: 'structure', id: 'totem_pole' } });
        break;
      default: return null;
    }
    if (!('time' in vars)) vars.time = clockOf(n);
    vars.n = numText(n);
    Object.assign(c, { n, d, skulls: skullsOf(d), reward: rewardFor(cfg, d, p, k),
      name: fillText(tc.name != null ? tc.name : '{target}', vars), text: fillText(tc.text || '', vars) });
    return c;
  }

  function roll(cfg, ctx, rnd) {
    const pool = eligibleTypes(cfg, ctx);
    const n = choicesOf(cfg);
    const out = [];
    while (out.length < n && pool.length) {
      const total = pool.reduce((a, e) => a + e.weight, 0);
      let r = rnd() * total, at = pool.length - 1;
      for (let i = 0; i < pool.length; i++) { r -= pool[i].weight; if (r < 0) { at = i; break; } }
      const type = pool[at].type;
      pool.splice(at, 1);
      const c = makeContract(cfg, type, ctx, rnd);
      if (c) out.push(c);
    }
    return out;
  }

  // ------------------------------------------------------------------ the context from the editor's data

  /** A small seeded generator (the page's Roll with a seed shows the same board again). */
  function mulberry32(seed) {
    let a = (seed >>> 0) || 1;
    return () => { a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  }

  const rowSingle = (r) => !Array.isArray(r.enemy) && String(r.enemy || '') !== 'roster';
  const rowElite = (r) => (r.elite == null || typeof r.elite === 'boolean' ? '' : String(r.elite));
  function rowEvery(r) {
    if (String(r.pace || '') === 'once') return 0;
    const v = r.every == null ? 30 : r.every;
    if (Array.isArray(v) && v.length) return (num(v[0], 30) + num(v[v.length - 1], 30)) * 0.5;
    return num(v, 30);
  }
  /** WaveTimeline.row_wave_times: every wave second of a waves / once row up to `end` and before its `until`. */
  function rowWaveTimes(r, end, limit) {
    const out = [];
    const p = String(r.pace || 'continuous');
    if (p !== 'waves' && p !== 'once') return out;
    const until = r.until != null ? num(r.until, Infinity) : Infinity;
    const every = rowEvery(r);
    const start = num(r.t, 0) + Math.max(num(r.offset, 0), 0);
    for (let k = 0; k < (limit || 10000); k++) {
      const tk = start + (every > 0 ? k * every : 0);
      if (tk >= until || tk > end) break;
      out.push(tk);
      if (every <= 0) break;
    }
    return out;
  }

  /**
   * The roll's context from the editor's data, as WantedBoard.context builds it from the Registry and the save:
   * o = {tl (timeline_data), map, stage, stages: [{name, start, end, boss}], creatures (/api/enemies records),
   *      weapons, lines (/api/items), hero (/api/heroes record), heroWeapons (base weapons by id), P, beaten,
   *      metAll (every creature met), seenAll (every item seen), unlocksDone (every unlock quest done)}
   */
  function contextFrom(o) {
    const tl = o.tl || {};
    const k = clamp(num(o.stage, 0), 0, Math.max((o.stages || []).length - 1, 0));
    const st = (o.stages || [])[k] || { name: 'Stage ' + (k + 1), start: 0, end: 1e9, boss: '' };
    const s0 = num(st.start, 0), s1 = num(st.end, 1e9);
    const byId = {};
    for (const c of o.creatures || []) byId[c.id] = c;
    const ok = (c) => c && !c.hidden && !c.retired && c.archetype !== 'boss' && c.brain !== 'dummy' && c.kind !== 'boss' && !String(c.id).startsWith('training_dummy');
    const met = (id) => !!o.metAll || (Array.isArray(o.met) && o.met.includes(id));
    const hero = o.hero || {};
    const weapons = o.weapons || [];
    const start = startWeaponFor(hero, weapons);
    const bd = st.boss ? byId[st.boss] : null;
    const ctx = { map: o.map || '', stage: k, stage_name: st.name, window: [s0, s1], P: num(o.P, 0), beaten: !!o.beaten,
      hero: { id: hero.id || '', name: hero.name || hero.id || '', start: start },
      boss: bd ? { id: bd.id, name: bd.name, met: met(bd.id) } : {} };
    const spans = {};
    for (const r of tl.roster || []) {
      if (!isObj(r) || !rowSingle(r) || rowElite(r) !== '' || r.special || String(r.pace || '') === 'once') continue;
      const a = Math.max(num(r.t, 0), s0), b = Math.min(r.until != null ? num(r.until, Infinity) : Infinity, s1);
      if (b <= a) continue;
      (spans[r.enemy] = spans[r.enemy] || []).push([a, b]);
    }
    ctx.creatures = Object.keys(spans).filter((id) => ok(byId[id])).sort().map((id) => {
      const c = byId[id];
      return { id, name: c.name, seconds: union(spans[id]), elite: c.archetype === 'elite', met: met(id),
        special: num(((c.variance || {}).special_chance), 0) > 0 };
    });
    const sp = isObj(tl.specials) ? tl.specials : {};
    ctx.gear = [];
    if (Object.keys(sp).length && s1 > num(sp.from, 0)) {
      for (const row of sp.pool || []) {
        const g = isObj(row) && num(row.stage, 1) <= k + 1 ? byId[row.enemy] : null;
        if (ok(g)) ctx.gear.push({ id: g.id, name: g.name, met: met(g.id) });
      }
    }
    ctx.elite_boss = [];
    let est = 0;
    for (const ev of tl.events || []) {
      if (!isObj(ev) || String(ev.type || '') !== 'elite_boss') continue;
      const t = num(ev.t, 0);
      if (t < s0 || t >= s1) continue;
      est += 1;
      for (const eid of Array.isArray(ev.enemy) ? ev.enemy : [ev.enemy]) {
        const ed = byId[eid];
        if (ok(ed) && !ctx.elite_boss.some((x) => x.id === ed.id)) ctx.elite_boss.push({ id: ed.id, name: ed.name, met: met(ed.id) });
      }
    }
    for (const r of tl.roster || []) {
      if (!isObj(r) || rowElite(r) === '') continue;
      for (const tk of rowWaveTimes(r, s1)) if (tk >= s0 && tk < s1) est += Math.max(Math.round(num(r.count, 1)), 1);
    }
    ctx.elite_estimate = est;
    const seen = (id) => !!o.seenAll || (Array.isArray(o.seen) && o.seen.includes(id));
    ctx.weapons = [];
    for (const w of weapons.slice().sort((a, b) => (a.id < b.id ? -1 : 1))) {
      if (w.is_evolution) continue;
      const own = w.id === start;
      if (!own) {
        if (w.hidden || (w.availability === 'locked' && !o.unlocksDone) || (w.hero && w.hero !== hero.id)) continue;
        if (num(w.from_stage, 0) > 0 && k + 1 < num(w.from_stage, 0)) continue;
      }
      const evo = w.evolution;
      ctx.weapons.push({ id: w.id, name: w.name_play || w.name, start: own, seen: own || seen(w.id), evolves: !!(evo && !evo.hidden),
        max_level: Math.max(Math.round(num(w.max_level, 5)), 1), icon: w.icon_play || w.icon });
    }
    ctx.cards = [];
    for (const p of o.lines || []) {
      if (p.hidden || (p.availability === 'locked' && !o.unlocksDone)) continue;
      if (num(p.from_stage, 0) > 0 && k + 1 < num(p.from_stage, 0)) continue;
      const ev = p.evolved;
      ctx.cards.push({ id: p.id, name: p.name, seen: seen(p.id), evolves: !!(ev && !ev.hidden), max_level: Math.max(Math.round(num(p.max_level, 4)), 1), icon: p.icon_play || p.icon });
    }
    taskContext(ctx, o, tl, k, seen);
    return ctx;
  }

  /** Pass 113 (lane TASKS): WantedBoard._task_context from the editor's data: passive_items, heal_items, heal_sources,
   *  totem_poles, elements. `o.passives` the /api/items passive items, `o.lines` its cards (with `evolved`), `o.sources`
   *  {pickups, structures} (/api/wanted/sources; none = no heal source, no Totem Pole). */
  function taskContext(ctx, o, tl, k, seen) {
    const okItem = (p) => p && !p.hidden && !(p.availability === 'locked' && !o.unlocksDone) && !(num(p.from_stage, 0) > 0 && k + 1 < num(p.from_stage, 0));
    ctx.passive_items = [];
    for (const p of (o.passives || []).slice().sort((a, b) => (a.id < b.id ? -1 : 1))) {
      if (p.line || p.evolves_from || !okItem(p)) continue;
      ctx.passive_items.push({ id: p.id, name: p.name, seen: seen(p.id), max_level: ladderTop(p) });
    }
    ctx.heal_items = [];
    const byId = {};
    for (const p of (o.lines || []).concat(o.passives || [])) { byId[p.id] = p; if (p.evolved) byId[p.evolved.id] = p.evolved; }
    const base = (o.lines || []).concat(o.passives || []).filter((p) => !p.evolves_from).sort((a, b) => (a.id < b.id ? -1 : 1));
    for (const p of base) {
      const evo = p.evolved || (p.evolves_into ? byId[p.evolves_into] : null);
      if (!(passiveHeals(p) || passiveHeals(evo)) || !okItem(p)) continue;
      ctx.heal_items.push({ id: p.id, name: p.name, kind: p.line ? 'card' : 'passive', seen: seen(p.id) });
    }
    const src = isObj(o.sources) ? o.sources : { pickups: [], structures: [] };
    const pk = {};
    for (const p of src.pickups || []) pk[p.id] = p;
    const ids = [];
    for (const r of (isObj(tl.pickups) ? tl.pickups.roster : null) || []) if (isObj(r) && num(r.weight, 0) > 0) ids.push(String(r.id || ''));
    for (const key of ['brown', 'black']) {
      const b = isObj(tl.barrels) ? tl.barrels[key] : null;
      if (isObj(b) && num(b.powerup_chance, 0) > 0) for (const r of b.powerups || []) if (isObj(r) && num(r.weight, 0) > 0) ids.push(String(r.id || ''));
    }
    ctx.heal_sources = [];
    for (const id of ids) {
      const p = pk[id];
      if (p && p.effect === 'heal' && !p.small && !p.credit_stat && !ctx.heal_sources.some((x) => x.kind === 'pickup' && x.id === id)) ctx.heal_sources.push({ kind: 'pickup', id, name: p.name || id });
    }
    let poles = 0;
    const plan = isObj(tl.structures) ? tl.structures : {};
    if (Object.keys(plan).length) {
      const roster = Array.isArray(plan.roster) ? plan.roster : [];
      const all = src.structures || [];
      const placed = (roster.length ? roster.map((id) => all.find((s) => s.id === id)).filter(Boolean) : all.slice()).filter((s) => !s.hidden).sort((a, b) => (a.id < b.id ? -1 : 1));
      for (const s of placed) {
        if (s.effect === 'heal' || (s.effect === 'dice' && (!Array.isArray(s.outcomes) || s.outcomes.includes('heal')))) ctx.heal_sources.push({ kind: 'structure', id: s.id, name: s.name || s.id });
        if (s.effect === 'totem') poles += isObj(s.per_map) ? Math.max(Math.round(num(s.per_map.min, 1)), 0) : 1;
      }
    }
    ctx.totem_poles = poles;
    ctx.elements = [];
    for (const el of ELEMENTS) if (elementReachable(el, ctx, o)) ctx.elements.push({ id: el, name: ELEMENT_NAMES[el] || el });
  }

  /** PassiveDef.ladder_top for an /api/items passive item record. */
  function ladderTop(p) {
    if (p.single) return 1;
    const i = Math.max(LADDER.indexOf(String(p.rarity || 'common')), 0);
    return LADDER.length - 1 - i + 2;
  }
  /** Whether a passive record's levels give the hero one of HEAL_STATS (TaskTally.passive_heals). */
  function passiveHeals(p) {
    if (!isObj(p)) return false;
    for (const lv of Array.isArray(p.levels) ? p.levels : []) {
      for (const e of Array.isArray(lv) ? lv : []) {
        const t = String((e && e.target) || 'player');
        if (isObj(e) && HEAL_STATS.includes(String(e.stat)) && num(e.value, 0) > 0 && !(t === 'all_weapons' || t.startsWith('weapon:') || t.startsWith('tag:'))) return true;
      }
    }
    return false;
  }
  /** Run.element_of for a record: its `element`, else a weapon's base fire / poison damage, else a passive's fire_* /
   *  poison_* stats. */
  function elementOf(rec) {
    if (!isObj(rec)) return '';
    if (rec.element) return String(rec.element);
    const b = isObj(rec.base) ? rec.base : null;
    if (b) { if (num(b.fire_damage, 0) > 0) return 'fire'; if (num(b.poison_damage, 0) > 0) return 'poison'; return ''; }
    for (const lv of Array.isArray(rec.levels) ? rec.levels : []) {
      for (const e of Array.isArray(lv) ? lv : []) {
        const st = String((e && e.stat) || '');
        if (st.startsWith('fire_')) return 'fire';
        if (st.startsWith('poison_')) return 'poison';
      }
    }
    return '';
  }
  /** WantedBoard._element_reachable: a weapon of the context (its own element, its path mutations'), a card or a passive
   *  item of it carries `el`. */
  function elementReachable(el, ctx, o) {
    const wById = {};
    for (const w of o.weapons || []) wById[w.id] = w;
    for (const w of ctx.weapons || []) {
      const rec = wById[w.id];
      if (!rec) continue;
      if (elementOf(rec) === el) return true;
      for (const m of rec.mutations || []) if (!m.hidden && !m.hero && String(m.element || '') === el) return true;
    }
    const pById = {};
    for (const p of (o.lines || []).concat(o.passives || [])) pById[p.id] = p;
    for (const x of (ctx.cards || []).concat(ctx.passive_items || [])) if (elementOf(pById[x.id]) === el) return true;
    return false;
  }

  /** Registry.start_weapon_for: his `start_weapon`, else the first base weapon (by id) that is his alone and not hidden,
   *  else his favourite, else the Peashooter. */
  function startWeaponFor(hero, weapons) {
    if (hero.start_weapon && weapons.some((w) => w.id === hero.start_weapon)) return hero.start_weapon;
    const own = weapons.filter((w) => !w.is_evolution && w.hero === hero.id && !w.hidden).sort((a, b) => (a.id < b.id ? -1 : 1));
    if (own.length) return own[0].id;
    if (hero.favourite_weapon && weapons.some((w) => w.id === hero.favourite_weapon)) return hero.favourite_weapon;
    return 'peashooter';
  }

  // ------------------------------------------------------------------ the checks the tab shows

  function issues(cfg) {
    const errors = [], warnings = [];
    if (!Array.isArray(cfg.tasks)) errors.push('tasks must be a list');
    const seenT = {};
    let anyOn = false;
    for (const t of cfg.tasks || []) {
      if (!isObj(t)) { errors.push('a task entry is not an object'); continue; }
      const type = String(t.type || '');
      if (!TYPES[type]) { errors.push(`unknown task type "${type}"`); continue; }
      if (seenT[type]) errors.push(`${type} is listed twice`);
      seenT[type] = true;
      if (t.on !== false && num(t.weight, 0) > 0) anyOn = true;
      if (num(t.weight, 0) < 0) errors.push(`${type}: a weight below 0`);
      const dif = t.difficulty;
      if (!Array.isArray(dif) || dif.length !== 2 || !dif.every((x) => isFinite(Number(x)))) errors.push(`${type}: difficulty is two numbers [easy end, hard end]`);
      else if (Number(dif[0]) < 0 || Number(dif[1]) < 0) errors.push(`${type}: a difficulty below 0`);
      if (TYPES[type].param) {
        if (!Array.isArray(t.n) || !t.n.length) errors.push(`${type}: no number range (n)`);
        else t.n.forEach((e, i) => { if (!Array.isArray(e) || e.length !== 2 || !e.every((x) => isFinite(Number(x)) && Number(x) >= 0)) errors.push(`${type}: stage ${i + 1}'s range is two numbers ≥ 0`); });
        if (num(t.step, 1) < 1) warnings.push(`${type}: a step under 1 rounds to 1`);
      }
      if (!String(t.text || '').trim()) warnings.push(`${type}: no task line`);
    }
    for (const type of TYPE_ORDER) if (!seenT[type]) warnings.push(`${type} is not in the list (it never comes)`);
    if (!anyOn) errors.push('every task type is off or weighs 0: the board could never post anything');
    const ch = num(cfg.choices, 3);
    if (ch < 1 || ch > MAX_CHOICES) warnings.push(`choices ${ch}: the board shows 1 to ${MAX_CHOICES} (it is clamped)`);
    if (num((cfg.unlock || {}).runs, 1) < 1) warnings.push('unlock.runs under 1 is read as 1: a first-time player never sees the board');
    const rw = cfg.reward || {};
    if (num(rw.base, 0) < 0 || num(rw.per_point, 0) < 0) errors.push('reward base and per point are 0 or more');
    return { errors, warnings };
  }

  return { TYPES, TYPE_ORDER, TYPE_INFO, DEFAULTS, MAX_CHOICES, normalized, taskCfg, union, targetsOf, eligibleTypes, typeChances,
    scaledRange, snapN, rollN, difficultyOf, skullsOf, rewardFor, fillText, clockOf, makeContract, roll, mulberry32,
    rowWaveTimes, contextFrom, startWeaponFor, issues, choicesOf,
    TARGET_FIRST, ELEMENT_NAMES, HEAL_STATS, targetRange, ladderTop, passiveHeals, elementOf };   // pass 113 (lane TASKS)
})();
if (typeof module !== 'undefined') module.exports = WantedModel;
