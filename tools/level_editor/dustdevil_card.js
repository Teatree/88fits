'use strict';
// Pass 113 (lane TWISTER; Garry: "Tornadoes still don't look like tornadoes and are quite confusing. Make them rarer
// too."): the Settings tab's Dust devils card. Its rows (dust_devils.*) are plain field rows drawn by settings.js from
// fields.js, greyed with the game's numbers; this file keeps a copy of game/core/systems/DustDevils.gd's DEFAULTS and its
// reader (config_of, count_in) and draws the line under the rows: about how many come in each stage, when, for how
// long, how big. selftest_TWISTER113.py runs it under Node and checks the copy against the GDScript.
const DustDevilCard = (() => {
  const DEFAULTS = {
    enabled: true, first: 90, every: [120, 180], life: [60, 90], max_alive: 1,
    radius: 3, speed: 1.4, wander: 'cross', miss: 3, form_dist: [7, 11],
    form_seconds: 2.5, fade_seconds: 2,
    toss: { up: 9.5, out: 3.6, cooldown: 1.2 }, lift: 1.7, lift_height: 4.5,
    size: 1.25, opacity: 0.7,
    warn: true, in_boss: false, in_portal: false, in_endless: false,
  };
  const WANDERS = ['cross', 'drift', 'loop'];
  const EVERY_MIN = 10;
  const HERO_REACH = 0.5;

  const isObj = (x) => x != null && typeof x === 'object' && !Array.isArray(x);
  const num = (v, fb) => (typeof v === 'number' && isFinite(v) ? v : (typeof v === 'boolean' ? (v ? 1 : 0) : (typeof v === 'string' && v.trim() !== '' && isFinite(Number(v)) ? Number(v) : fb)));
  const bool = (v) => (typeof v === 'boolean' ? v : (typeof v === 'number' ? v !== 0 : (typeof v === 'string' ? ['true', '1', 'yes', 'on'].includes(v.toLowerCase()) : false)));
  function rangeOf(v, fb) {
    if (typeof v === 'number' && isFinite(v)) return [v, v];
    if (Array.isArray(v) && v.length) { const a = num(v[0], fb[0]); const b = num(v[v.length - 1], a); return [Math.min(a, b), Math.max(a, b)]; }
    return fb.slice();
  }

  /** The block whole, every key filled and in range, as the game reads it (DustDevils.config_of). */
  function configOf(block) {
    const b = isObj(block) ? block : {};
    const o = JSON.parse(JSON.stringify(DEFAULTS));
    for (const k of Object.keys(b)) {
      if (k === 'toss' && isObj(b.toss)) Object.assign(o.toss, b.toss);
      else o[k] = b[k];
    }
    o.enabled = bool(o.enabled);
    o.first = Math.max(num(o.first, 90), 0);
    const ev = rangeOf(o.every, [120, 180]);
    o.every = [Math.max(ev[0], EVERY_MIN), Math.max(ev[1], EVERY_MIN)];
    const lf = rangeOf(o.life, [60, 90]);
    o.form_seconds = Math.max(num(o.form_seconds, 2.5), 0.1);
    o.fade_seconds = Math.max(num(o.fade_seconds, 2), 0.1);
    const least = o.form_seconds + o.fade_seconds + 1;
    o.life = [Math.max(lf[0], least), Math.max(lf[1], least)];
    o.max_alive = Math.max(Math.trunc(num(o.max_alive, 1)), 0);
    o.radius = Math.max(num(o.radius, 3), 0.2);
    o.speed = Math.max(num(o.speed, 1.4), 0);
    o.wander = WANDERS.includes(String(o.wander)) ? String(o.wander) : 'cross';
    o.miss = num(o.miss, 3);
    const fd = rangeOf(o.form_dist, [7, 11]);
    o.form_dist = [Math.max(fd[0], 0), Math.max(fd[1], Math.max(fd[0], 0))];
    const ts = isObj(o.toss) ? o.toss : {};
    o.toss = { up: Math.max(num(ts.up, 9.5), 0), out: num(ts.out, 3.6), cooldown: Math.max(num(ts.cooldown, 1.2), 0) };
    o.lift = Math.max(num(o.lift, 1.7), 0);
    // pass 115 (lane POLISH): how high a creature rides, the funnel's size, how solid it is
    o.lift_height = Math.max(num(o.lift_height, 4.5), 0);
    o.size = Math.min(Math.max(num(o.size, 1.25), 0.25), 4);
    o.opacity = Math.min(Math.max(num(o.opacity, 0.7), 0.5), 1);
    for (const k of ['warn', 'in_boss', 'in_portal', 'in_endless']) o[k] = bool(o[k]);
    return o;
  }

  /** About how many come in `length` seconds of a stage's own clock (DustDevils.count_in). */
  function countIn(c, length) {
    if (!c.enabled || length < c.first) return 0;
    return 1 + Math.floor((length - c.first) / Math.max((c.every[0] + c.every[1]) / 2, EVERY_MIN));
  }

  const mmss = (s) => { const m = Math.floor(s / 60); const r = Math.round(s - m * 60); return `${m}:${String(r).padStart(2, '0')}`; };
  const span = (r, unit) => (r[0] === r[1] ? `${r[0]} ${unit}` : `${r[0]} to ${r[1]} ${unit}`);

  /** One paragraph: how many a stage, when, how long, how big, what the reach is. `stages` [{name, length}]. */
  function summaryText(block, stages) {
    const c = configOf(block);
    if (!c.enabled) return 'Off: no dust devils on this map.';
    const per = (stages || []).map((w) => `${countIn(c, w.length)} in ${w.name}`).join(', ');
    const ev = c.every[0] === c.every[1] ? `every ${mmss(c.every[0])}` : `every ${mmss(c.every[0])} to ${mmss(c.every[1])}`;
    const extra = [c.in_boss ? 'the boss fight' : '', c.in_portal ? 'the portal countdown' : '', c.in_endless ? 'Endless' : ''].filter(Boolean);
    return `About ${per || 'a few a stage'} (each stage's own time${extra.length ? ` plus ${extra.join(', ')}` : ''}): the first at ${mmss(c.first)}, then one ${ev}, ` +
      `at most ${c.max_alive} at once. Each forms on the screen ${span(c.form_dist, 'm')} from the hero (its dust first, the funnel rising over ${c.form_seconds} s), ` +
      `lasts ${span(c.life, 's')} and fades over ${c.fade_seconds} s. It throws the hero inside its ring (${(c.radius + HERO_REACH).toFixed(1)} m, drawn on the sand) ` +
      `${c.toss.up} m/s up (about ${(c.toss.up * c.toss.up / 48).toFixed(1)} m high) and ${c.toss.out} m/s out, and lifts creatures within ${c.radius} m for ${c.lift} s, ${c.lift_height} m up (× their size). ` +
      `Its funnel is ${(7 * c.size).toFixed(1)} m tall, ${Math.round(c.opacity * 100)}% solid. ${c.warn ? 'The first one of a run says "DUST DEVIL".' : 'No toast.'}`;
  }

  /** The card's extra block: the paragraph and any warnings (drawn under the rows by settings.js). */
  function block(tl) {
    const { el } = U;
    const stages = (typeof App !== 'undefined' && App.stageList) ? App.stageList().map((w) => ({ name: w.name, length: w.length })) : [];
    const wrap = el('div', { class: 'dustdevil-card' });
    wrap.appendChild(el('p', { class: 'muted small dustdevil-summary', text: summaryText(tl.dust_devils, stages) }));
    for (const w of issues(tl)) wrap.appendChild(el('p', { class: 'warn-text small', text: w }));
    return wrap;
  }

  /** Warnings (never errors) for a block that reads as a mistake. */
  function issues(tl) {
    const b = tl && tl.dust_devils;
    const out = [];
    if (!isObj(b)) return out;
    const c = configOf(b);
    if (!c.enabled) return out;
    if (c.life[1] >= c.every[0] && c.max_alive <= 1) out.push('Dust devils: a life as long as the gap between two means one is nearly always up (and the next waits for it to go).');
    if (c.max_alive === 0) out.push('Dust devils: Max alive 0 means none ever comes; switch them off instead.');
    if (c.form_dist[0] < c.radius + HERO_REACH + 1) out.push(`Dust devils: one may form ${c.form_dist[0]} m from the hero, inside or at the edge of its own ring: he gets no warning.`);
    return out;
  }

  const api = { DEFAULTS, WANDERS, EVERY_MIN, HERO_REACH, configOf, countIn, summaryText, block, issues };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  return api;
})();
