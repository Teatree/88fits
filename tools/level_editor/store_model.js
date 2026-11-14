'use strict';
// Pass 149 (lane EDITOR): the Store's page-free maths (game/content/store/store.json version 2, docs/store_schema.md; the
// game reads it in game/core/systems/StorePacks.gd, lane STORE). Shared by the Store tab (store.js) and
// selftest_GEMS149.py, which runs it under Node and checks coinsFor against the game's fixture
// game/tests/fixtures/pass149_store_coins.json. Nothing here touches the page.
//
// Garry (2026-11-14): "In the Shop there will now be 2 sections: Gems section at the top, Coins section underneath:
// Gems are bought with $ ... Coins are bought with Gems. As the Player progresses the amount of Coins they get from each
// offers changes ... in rounded steps rather than continuously ... Latest Stage currently unlocked ... a bigger weight
// ... Their Trail Power Level ... a lower weight".
//
//   normalise(raw)           the file with its missing blocks filled in (a copy; a key it does not know is kept)
//   isV2(raw)                whether a file is version 2 (a version 1 file is pass 147's coin packs)
//   fromV1(raw)              a version 2 file made from the defaults, for a page that read a version 1 file
//   dollars(cents)           a price in whole dollars, rounded up ($4.99 -> 5), at least 1 (StorePacks.dollars)
//   gemBonus(data)           {pack id: N}: "+N% BONUS" = gems per whole dollar against the cheapest pack's (pass 147's rule)
//   offerBonus(data, s, T)   {offer id: N}: coins per gem against the offer with the fewest gems, at the amounts shown
//   nice(v, sig)             v rounded to `sig` significant figures (0 for v <= 0)
//   stageMult(scaling, s)    stage_mult[s], the last value holding past its end
//   coinsFor(offer, s, T, scaling)   the coin offer rule (COMMON.md decision 2): nice(coins x stage_mult[s] x (1 +
//                            trail_per_step x floor(T / trail_step)), round_sig)
//   preview(data, stages, levels)    every offer's coins at every stage x Trail level: [{offer, rows: [{stage, cells}]}]
//   check(data, ctx)         [{sev: error|warn, path, text}]; ctx {currencies: [ids], stages: n, pictures: [res paths]}
//
// As a command: node store_model.js <store.json> prints the checks and exits 1 on an error.
const StoreModel = (() => {
  const RIBBONS = ['', 'most_popular', 'best_value'];
  const RIBBON_WORDS = { '': 'none', most_popular: 'Most popular', best_value: 'Best value' };
  const PREVIEW_LEVELS = [0, 10, 20, 40, 60, 83];
  // COMMON.md decision 1 (the lead's): the gem tiers as remembered from Survivor.io, the three coin offers, the scaling, the
  // paid revive off (price 0)
  const DEFAULTS = {
    version: 2,
    gems: { currency: 'gems', show_bonus: true, packs: [
      { id: 'gems_handful', amount: 80, price_cents: 99, price_text: '$0.99', ribbon: '', picture: 'res://art/ui/store/gems_handful.png' },
      { id: 'gems_pile', amount: 500, price_cents: 499, price_text: '$4.99', ribbon: '', picture: 'res://art/ui/store/gems_pile.png' },
      { id: 'gems_pouch', amount: 1200, price_cents: 999, price_text: '$9.99', ribbon: 'most_popular', picture: 'res://art/ui/store/gems_pouch.png' },
      { id: 'gems_box', amount: 2500, price_cents: 1999, price_text: '$19.99', ribbon: '', picture: 'res://art/ui/store/gems_box.png' },
      { id: 'gems_chest', amount: 6500, price_cents: 4999, price_text: '$49.99', ribbon: '', picture: 'res://art/ui/store/gems_chest.png' },
      { id: 'gems_vault', amount: 14000, price_cents: 9999, price_text: '$99.99', ribbon: 'best_value', picture: 'res://art/ui/store/gems_vault.png' }] },
    coins: { currency: 'gold', pay: 'gems', show_bonus: true,
      offers: [
        { id: 'coins_small', gems: 100, coins: 1000, ribbon: '', picture: 'res://art/ui/store/pack_handful.png' },
        { id: 'coins_medium', gems: 500, coins: 5500, ribbon: 'most_popular', picture: 'res://art/ui/store/pack_sack.png' },
        { id: 'coins_large', gems: 1200, coins: 14000, ribbon: 'best_value', picture: 'res://art/ui/store/pack_cart.png' }],
      scaling: { stage_mult: [1.0, 3.0, 7.0, 14.0], trail_step: 10, trail_per_step: 0.05, round_sig: 2 } },
    revive: { price: 0, currency: 'gems', per_run: 1 },
  };
  const SCALING = DEFAULTS.coins.scaling;

  const isObj = (x) => x != null && typeof x === 'object' && !Array.isArray(x);
  const isNum = (x) => typeof x === 'number' && Number.isFinite(x);
  const isInt = (x) => Number.isInteger(x);
  const clone = (x) => (x === undefined ? undefined : JSON.parse(JSON.stringify(x)));
  const num = (x, d) => (isNum(x) ? x : d);
  const ID_RE = /^[a-z0-9_]+$/;

  function isV2(raw) { return isObj(raw) && Number(raw.version) === 2; }

  /** The file with every block the tab edits present (a copy). Present keys are kept as they are, unknown ones too. */
  function normalise(raw) {
    const d = isObj(raw) ? clone(raw) : {};
    if (d.version == null) d.version = 2;
    if (!isObj(d.gems)) d.gems = { currency: 'gems', show_bonus: true, packs: [] };
    if (typeof d.gems.currency !== 'string') d.gems.currency = 'gems';
    if (typeof d.gems.show_bonus !== 'boolean') d.gems.show_bonus = true;
    if (!Array.isArray(d.gems.packs)) d.gems.packs = [];
    if (!isObj(d.coins)) d.coins = { currency: 'gold', pay: 'gems', show_bonus: true, offers: [] };
    if (typeof d.coins.currency !== 'string') d.coins.currency = 'gold';
    if (typeof d.coins.pay !== 'string') d.coins.pay = 'gems';
    if (typeof d.coins.show_bonus !== 'boolean') d.coins.show_bonus = true;
    if (!Array.isArray(d.coins.offers)) d.coins.offers = [];
    if (!isObj(d.coins.scaling)) d.coins.scaling = clone(SCALING);
    if (!isObj(d.revive)) d.revive = clone(DEFAULTS.revive);
    return d;
  }
  /** A version 1 file (pass 147: coin packs bought with dollars) has no gems: the tab starts version 2 from the defaults. */
  function fromV1() { return clone(DEFAULTS); }

  // ------------------------------------------------------------------ the bonus tags

  function dollars(cents) { return Math.max(Math.ceil(num(cents, 0) / 100), 1); }
  /** StorePacks.bonus_for: N = round(100 x (have / (per x base) - 1)), nothing under 1. */
  function bonusOf(rate, base) {
    if (!(base > 0) || !(rate > 0)) return 0;
    const n = Math.round(100 * (rate / base - 1));
    return n >= 1 ? n : 0;
  }
  /** {pack id: N}: a gem pack's gems per whole dollar against the cheapest pack's (pass 147's rule, gems for coins). */
  function gemBonus(data) {
    const g = isObj(data) && isObj(data.gems) ? data.gems : {};
    const packs = (Array.isArray(g.packs) ? g.packs : []).filter(isObj);
    const out = {};
    let best = -1, base = 0;
    for (const p of packs) {
      const c = num(p.price_cents, 0);
      if (c > 0 && (best < 0 || c < best)) { best = c; base = num(p.amount, 0) / dollars(c); }
    }
    for (const p of packs) out[p.id] = g.show_bonus === false || !(num(p.price_cents, 0) > 0) ? 0 : bonusOf(num(p.amount, 0) / dollars(p.price_cents), base);
    return out;
  }
  /** {offer id: N}: an offer's coins per gem against the offer with the fewest gems, both at the amounts shown at stage
   *  index `s` and Trail Level `T` (coinsFor; 0 and 0 by default: the amounts a new player reads). Lane STORE's rule. */
  function offerBonus(data, s, T) {
    const c = isObj(data) && isObj(data.coins) ? data.coins : {};
    const offers = (Array.isArray(c.offers) ? c.offers : []).filter(isObj);
    const sc = isObj(c.scaling) ? c.scaling : SCALING;
    const shown = (o) => coinsFor(o, num(s, 0), num(T, 0), sc);
    const out = {};
    let best = -1, base = 0;
    for (const o of offers) {
      const g = num(o.gems, 0);
      if (g > 0 && (best < 0 || g < best)) { best = g; base = shown(o) / g; }
    }
    for (const o of offers) out[o.id] = c.show_bonus === false || !(num(o.gems, 0) > 0) ? 0 : bonusOf(shown(o) / num(o.gems, 1), base);
    return out;
  }

  // ------------------------------------------------------------------ the coin offer rule (COMMON.md decision 2)

  /** v rounded to `sig` significant figures, half away from zero, counted on the whole part's digits: 17,325 -> 17,000
   *  at 2, 7.4 -> 7. The power of ten is found by stepping, not by a logarithm (log10(1000) can come out a hair under 3).
   *  0 for v <= 0. */
  function nice(v, sig) {
    const s = Math.max(1, Math.round(num(sig, 2)));
    if (!(v > 0)) return 0;
    let e = 0, p = 1;
    while (p * 10 <= v) { p *= 10; e++; }
    while (p > v) { p /= 10; e--; }
    const mag = Math.pow(10, e - s + 1);
    return Math.round(Math.round(v / mag) * mag);
  }
  /** stage_mult[s]; s below 0 reads 0, past the list's end the last value holds; 1 with no list. */
  function stageMult(scaling, s) {
    const sm = isObj(scaling) && Array.isArray(scaling.stage_mult) && scaling.stage_mult.length ? scaling.stage_mult : [1];
    return num(sm[Math.max(0, Math.min(Math.trunc(num(s, 0)), sm.length - 1))], 1);
  }
  /** The steps the Trail Level has climbed: floor(T / trail_step); a trail_step of 0 or less = no Trail steps. */
  function trailSteps(scaling, T) {
    const step = Math.trunc(num(isObj(scaling) ? scaling.trail_step : undefined, SCALING.trail_step));
    if (step <= 0) return 0;
    return Math.floor(Math.max(0, Math.trunc(num(T, 0))) / step);
  }
  /** The factor before rounding: stage_mult[s] x (1 + trail_per_step x floor(T / trail_step)). */
  function factor(scaling, s, T) {
    const sc = isObj(scaling) ? scaling : SCALING;
    return stageMult(sc, s) * (1 + num(sc.trail_per_step, SCALING.trail_per_step) * trailSteps(sc, T));
  }
  /** The coins offer `offer` gives at stage index `s` (the latest unlocked) and Trail Level `T`: COMMON.md decision 2,
   *  multiplied in the rule's order (coins x stage x trail) then rounded to round_sig figures. */
  function coinsFor(offer, s, T, scaling) {
    const sc = isObj(scaling) ? scaling : SCALING;
    const coins = num(isObj(offer) ? offer.coins : offer, 0);
    const raw = coins * stageMult(sc, s) * (1 + num(sc.trail_per_step, SCALING.trail_per_step) * trailSteps(sc, T));
    return nice(raw, num(sc.round_sig, SCALING.round_sig));
  }
  /** Every offer at every stage (rows) x Trail level (columns). `stages` [{name}] (or a count), `levels` [T]. */
  function preview(data, stages, levels) {
    const d = normalise(data);
    const st = Array.isArray(stages) ? stages : Array.from({ length: Math.max(1, num(stages, 4)) }, (_, i) => ({ name: `Stage ${i + 1}` }));
    const lv = Array.isArray(levels) && levels.length ? levels : PREVIEW_LEVELS;
    return d.coins.offers.filter(isObj).map((o) => ({
      offer: o, gems: num(o.gems, 0),
      rows: st.map((s, i) => ({ stage: i, name: (isObj(s) && s.name) || `Stage ${i + 1}`, mult: stageMult(d.coins.scaling, i),
        cells: lv.map((T) => { const c = coinsFor(o, i, T, d.coins.scaling); return { T, coins: c, per_gem: num(o.gems, 0) > 0 ? c / o.gems : 0 }; }) })),
    }));
  }
  /** The levels the preview shows: 0, 10, 20, 40, 60 and the Trail's top (83 when the Trail is not known). */
  function previewLevels(top) {
    const t = isInt(top) && top > 0 ? top : 83;
    return Array.from(new Set(PREVIEW_LEVELS.slice(0, -1).filter((x) => x < t).concat([t])));
  }

  // ------------------------------------------------------------------ checks

  function check(data, ctx) {
    const out = [];
    const c = isObj(ctx) ? ctx : {};
    const add = (sev, path, text) => out.push({ sev, path, text });
    const err = (p, t) => add('error', p, t), warn = (p, t) => add('warn', p, t);
    if (!isObj(data)) { err('', 'The file is not a JSON object'); return out; }
    if (Number(data.version) !== 2) err('version', `version must be 2 (the file says ${data.version == null ? 'nothing' : data.version})`);
    const curs = Array.isArray(c.currencies) && c.currencies.length ? new Set(c.currencies) : null;
    const pics = Array.isArray(c.pictures) ? new Set(c.pictures) : null;
    const knownCur = (path, v, what) => {
      if (typeof v !== 'string' || !ID_RE.test(v)) err(path, `${what} must be a currency id`);
      else if (curs && !curs.has(v)) err(path, `${what} "${v}" is not in content/currencies (${Array.from(curs).join(', ')})`);
    };
    const ids = new Map();
    const item = (path, x, what) => {
      if (typeof x.id !== 'string' || !ID_RE.test(x.id)) { err(`${path}.id`, `${what}: the id must be lower-case letters, digits, _`); return; }
      if (ids.has(x.id)) err(`${path}.id`, `${x.id}: the id is used twice (${ids.get(x.id)} and ${path})`); else ids.set(x.id, path);
      if (x.ribbon != null && !RIBBONS.includes(x.ribbon)) err(`${path}.ribbon`, `${x.id}: unknown ribbon "${x.ribbon}" (none, most_popular, best_value)`);
      if (typeof x.picture !== 'string' || !x.picture) warn(`${path}.picture`, `${x.id}: no picture (the game shows the currency's icon)`);
      else if (!/^res:\/\//.test(x.picture)) err(`${path}.picture`, `${x.id}: the picture is a res:// path`);
      else if (pics && !pics.has(x.picture)) warn(`${path}.picture`, `${x.id}: no file ${x.picture} yet (the game shows the currency's icon until it lands)`);
    };
    // the gems
    const g = isObj(data.gems) ? data.gems : null;
    if (!g) err('gems', 'gems must be {currency, show_bonus, packs}');
    else {
      knownCur('gems.currency', g.currency, 'gems.currency');
      if (!Array.isArray(g.packs)) err('gems.packs', 'gems.packs must be a list');
      else {
        if (!g.packs.length) warn('gems.packs', 'No gem pack: the GEMS section is empty');
        g.packs.forEach((p, i) => {
          const at = `gems.packs.${i}`;
          if (!isObj(p)) { err(at, `Gem pack ${i + 1} is not an object`); return; }
          item(at, p, `Gem pack ${i + 1}`);
          const id = p.id || `pack ${i + 1}`;
          if (!isInt(p.amount) || p.amount <= 0) err(`${at}.amount`, `${id}: amount must be a whole number of gems above 0`);
          if (!isInt(p.price_cents) || p.price_cents <= 0) err(`${at}.price_cents`, `${id}: price_cents must be a whole number of cents above 0`);
          const pt = typeof p.price_text === 'string' ? p.price_text : '';
          if (!pt) err(`${at}.price_text`, `${id}: no price_text (what the button reads, "$4.99")`);
          else if (isInt(p.price_cents) && !pt.includes(`${Math.floor(p.price_cents / 100)}.${String(p.price_cents % 100).padStart(2, '0')}`)) err(`${at}.price_text`, `${id}: price_text "${pt}" does not name price_cents ${p.price_cents}`);
        });
      }
    }
    // the coins
    const k = isObj(data.coins) ? data.coins : null;
    if (!k) err('coins', 'coins must be {currency, pay, show_bonus, offers, scaling}');
    else {
      knownCur('coins.currency', k.currency, 'coins.currency (what an offer gives)');
      knownCur('coins.pay', k.pay, 'coins.pay (what an offer costs)');
      if (typeof k.currency === 'string' && k.currency === k.pay) err('coins.pay', 'an offer would pay and give the same currency');
      if (!Array.isArray(k.offers)) err('coins.offers', 'coins.offers must be a list');
      else {
        if (!k.offers.length) warn('coins.offers', 'No coin offer: the COINS section is empty');
        k.offers.forEach((o, i) => {
          const at = `coins.offers.${i}`;
          if (!isObj(o)) { err(at, `Coin offer ${i + 1} is not an object`); return; }
          item(at, o, `Coin offer ${i + 1}`);
          const id = o.id || `offer ${i + 1}`;
          if (!isInt(o.gems) || o.gems <= 0) err(`${at}.gems`, `${id}: gems (its price) must be a whole number above 0`);
          if (!isInt(o.coins) || o.coins <= 0) err(`${at}.coins`, `${id}: coins (at stage 1, Trail Level 0) must be a whole number above 0`);
        });
      }
      const sc = k.scaling;
      if (!isObj(sc)) err('coins.scaling', 'coins.scaling must be {stage_mult, trail_step, trail_per_step, round_sig}');
      else {
        const sm = sc.stage_mult;
        if (!Array.isArray(sm) || !sm.length || !sm.every((x) => isNum(x) && x > 0)) err('coins.scaling.stage_mult', 'stage_mult must be a list of numbers above 0, one a stage');
        else {
          if (sm.some((x, i) => i > 0 && x < sm[i - 1])) warn('coins.scaling.stage_mult', 'stage_mult goes down somewhere: a later stage would give fewer coins');
          const n = isInt(c.stages) ? c.stages : null;
          if (n && sm.length < n) warn('coins.scaling.stage_mult', `stage_mult has ${sm.length} value${sm.length === 1 ? '' : 's'} for ${n} stages: the last one holds for the rest`);
          if (n && sm.length > n) warn('coins.scaling.stage_mult', `stage_mult has ${sm.length} values for ${n} stages: the extra ones are never used`);
        }
        if (!isInt(sc.trail_step) || sc.trail_step < 0) err('coins.scaling.trail_step', 'trail_step must be a whole number of Trail levels, 0 or more (0 = the Trail never grows the offers)');
        else if (sc.trail_step === 0 && num(sc.trail_per_step, 0) > 0) warn('coins.scaling.trail_step', 'trail_step 0: the Trail never grows the offers (per step is not used)');
        if (!isNum(sc.trail_per_step) || sc.trail_per_step < 0) err('coins.scaling.trail_per_step', 'trail_per_step must be a number, 0 or more (0.05 = +5% a step)');
        if (!isInt(sc.round_sig) || sc.round_sig < 1) err('coins.scaling.round_sig', 'round_sig must be a whole number of significant figures, 1 or more');
        else if (sc.round_sig > 6) warn('coins.scaling.round_sig', `round_sig ${sc.round_sig}: the amounts hardly round at all (Garry: they move in rounded steps)`);
      }
    }
    // the paid revive
    const r = data.revive;
    if (!isObj(r)) err('revive', 'revive must be {price, currency, per_run}');
    else {
      if (!isInt(r.price) || r.price < 0) err('revive.price', 'revive.price must be a whole number, 0 or more (0 = no paid revive)');
      knownCur('revive.currency', r.currency, 'revive.currency');
      if (!isInt(r.per_run) || r.per_run < 0) err('revive.per_run', 'revive.per_run must be a whole number, 0 or more');
      else if (isInt(r.price) && r.price > 0 && r.per_run === 0) warn('revive.per_run', 'a paid revive with per_run 0 is never offered');
    }
    // one "most popular" and one "best value" a section read best
    for (const sec of [['gems.packs', g && g.packs], ['coins.offers', k && k.offers]]) {
      const list = Array.isArray(sec[1]) ? sec[1].filter(isObj) : [];
      for (const rb of ['most_popular', 'best_value']) { const n = list.filter((x) => x.ribbon === rb).length; if (n > 1) warn(sec[0], `${n} items wear the ribbon ${RIBBON_WORDS[rb]} in ${sec[0]}`); }
    }
    return out;
  }
  const errorsOf = (issues) => issues.filter((x) => x.sev === 'error');

  return { RIBBONS, RIBBON_WORDS, PREVIEW_LEVELS, DEFAULTS, SCALING, isV2, normalise, fromV1, dollars, bonusOf, gemBonus, offerBonus, nice, stageMult, trailSteps, factor, coinsFor, preview, previewLevels, check, errorsOf };
})();
if (typeof module !== 'undefined') {
  module.exports = StoreModel;
  if (require.main === module) {
    const fs = require('fs');
    const file = process.argv[2];
    if (!file) { console.error('usage: node store_model.js <store.json>'); process.exit(2); }
    const data = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^﻿/, ''));
    const issues = StoreModel.check(data, null);
    for (const x of issues) console.log(`${x.sev === 'error' ? 'ERROR' : 'warn '} ${x.path}: ${x.text}`);
    const bad = StoreModel.errorsOf(issues).length;
    console.log(`${bad} error${bad === 1 ? '' : 's'}, ${issues.length - bad} warning${issues.length - bad === 1 ? '' : 's'}`);
    process.exit(bad ? 1 : 0);
  }
}
