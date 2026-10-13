'use strict';
// Pass 72 (lane BOSS): the Settings tab's "Boss HP" card below the five numbers fields.js lists (boss_hp_scaling.enabled,
// exponent, window, min, max): the reference DPS of every boss the timeline brings, a chart of the HP multiplier and
// the fight's length against the hero's DPS (the reference marked, the floor and the ceiling shaded, a crosshair that
// reads any DPS), and the thinking in plain words. Garry: "Boss HP should be pegged to Player DPS ... It shouldn't be
// 1 to 1, so there is still a 'reward' in getting more DPS ... Add this setting to LevelEditor and explain your
// thinking. Don't forget to visualize the HP scaling". The maths are boss_model.js (the game's WaveTimeline.boss_hp_mult).
const BossScaling = (() => {
  const { el, svg, fmtN, fmtT } = U;
  const M = BossModel;
  let chosen = null;          // the boss the chart shows (an id), kept across redraws

  const WORDS = [
    'Why: a strong build melts a boss in seconds, a weak one is stuck with it for minutes. When a boss arrives the game reads the hero\'s damage a second over the last <b>window</b> seconds (what his hits really took off creatures, the same numbers as the Results screen) and gives the boss <b>(his DPS ÷ the boss\'s reference DPS) ^ exponent</b> times its HP, held between the floor and the ceiling.',
    'Why not 1 to 1: if the HP grew as fast as the DPS, every fight would last the same and a stronger build would be worth nothing against a boss. With the exponent <b>0.5</b> the HP grows with the square root of the DPS: <b>twice</b> the reference DPS gives the boss 1.41 times its HP and the fight is still <b>29% shorter</b>; four times: twice the HP, the fight half as long. Exponent 0 = never scaled, 1 = every fight as long as at the reference.',
    'The <b>floor</b> (0.75) gives a weak build a softer boss but never a pushover; the <b>ceiling</b> (3×) keeps a monster build from a sponge. The <b>references</b> are the DPS of the builds the difficulty was tuned on (tools/difficulty_probe.gd before each boss: Calavera and Drifter, the stage\'s build and Upgrade board): a hero at the reference meets the boss exactly as before. The debug arena never scales.',
    'A caution: the DPS counts only what a hit took off (a 500 hit on a 20 HP goblin is 20), so when the crowd dies faster than it comes, the DPS shows the crowd more than the build. In endless a returning boss\'s reference grows with its own HP growth since its stage.',
  ];

  /** The card's own block (after fields.js's five rows): the references, the chart, the words. */
  function block(tl) {
    const wrap = el('div', { class: 'bscale' });
    const cfg = M.scalingOf(tl);
    const bosses = M.bossEvents(tl);
    if (!cfg.present) wrap.appendChild(el('p', { class: 'muted small', text: 'This map has no boss_hp_scaling block: it plays the game\'s defaults (on, the grey numbers: the measured reference DPS of each boss). Untick "Peg boss HP to DPS" to keep every boss at its data HP.' }));
    // the references, one row a boss
    const refs = el('div', { class: 'bscale-refs' });
    refs.appendChild(el('h3', { class: 'block-title', text: 'Reference DPS (the DPS a boss is tuned for)' }));
    for (const b of bosses) {
      const creature = App.creature(b.id) || null;
      const gdef = M.REF_DEFAULTS[b.id];
      const def = { key: `boss_hp_scaling.ref_dps.${b.id}`, label: `${creature ? creature.name : b.id} · ${fmtT(b.t)}`, type: 'number', min: 0, step: 50, def: gdef,
        help: `${b.id}'s reference DPS: the hero's damage a second over the window when it arrives at which it keeps its data HP (×1). 0 = this boss is never scaled; empty = ${gdef ? 'the game\'s ' + gdef : 'never scaled (the game has no reference for it)'}. Measured with tools/difficulty_probe.gd (the DPS45 line) over the 45 s before ${fmtT(b.t)}.` };
      const base = M.bossBaseHp(creature, tl, b.stage);
      const ref = M.num(cfg.ref[b.id], 0);
      const note = ref > 0 ? `HP ${fmtN(base, 0)} at ×1 · at 2× this DPS: ${fmtN(base * M.hpMult(cfg, ref * 2, ref), 0)}` : 'never scaled';
      refs.appendChild(Forms.fieldRow(def, tl, { after: el('span', { class: 'muted small', text: ' ' + note }) }));
    }
    if (!bosses.length) refs.appendChild(el('p', { class: 'muted small', text: 'The timeline brings no boss event.' }));
    wrap.appendChild(refs);
    // the chart
    if (!chosen || !bosses.some((b) => b.id === chosen)) chosen = (bosses.find((b) => M.num(cfg.ref[b.id], 0) > 0) || bosses[0] || {}).id || null;
    const pick = el('div', { class: 'bscale-pick' }, el('span', { class: 'muted small', text: 'Chart for ' }));
    for (const b of bosses) {
      const c = App.creature(b.id);
      pick.appendChild(el('button', { class: 'btn small' + (b.id === chosen ? ' primary' : ''), type: 'button', text: c ? c.name : b.id, onclick: () => { chosen = b.id; App.render('tab'); } }));
    }
    wrap.appendChild(pick);
    const b = bosses.find((x) => x.id === chosen);
    if (b) wrap.appendChild(chart(tl, cfg, b));
    // the thinking
    const words = el('details', { class: 'bscale-words', open: true }, el('summary', { text: 'How it works, and why' }));
    for (const w of WORDS) { const p = el('p', { class: 'small' }); p.innerHTML = w; words.appendChild(p); }
    wrap.appendChild(words);
    return wrap;
  }

  /** The chart for boss `b`: x = the hero's DPS on a doubling scale (an eighth of the reference to 16 times it, the
   *  reference in the middle), left axis the HP multiplier (blue), right axis the fight's length against the fight at the
   *  reference with the scaling (orange) and without (dashed grey); the floor and the ceiling shaded; a crosshair reads it. */
  function chart(tl, cfg, b) {
    const creature = App.creature(b.id);
    const base = M.bossBaseHp(creature, tl, b.stage);
    const ref = M.num(cfg.ref[b.id], 0);
    const box = el('div', { class: 'bscale-chart' });
    if (!(ref > 0)) { box.appendChild(el('p', { class: 'muted small', text: `${b.id} has no reference DPS: it keeps its data HP whatever the hero deals.` })); return box; }
    const LO = 3, HI = 4;   // 2^-3 .. 2^4 of the reference
    const W = 640, H = 300, L = 54, R = 58, T = 18, B = 46;
    const pts = M.chartSeries(cfg, ref, LO, HI, 200);
    const maxM = Math.max(cfg.max, 1) + 0.25;
    const maxF = 2.5;   // the fight axis: up to 250% of the reference fight
    const x = (e) => L + (W - L - R) * (e + LO) / (LO + HI);
    const xd = (d) => x(Math.log2(Math.max(d, 1e-9) / ref));
    const yM = (m) => T + (H - T - B) * (1 - m / maxM);
    const yF = (f) => T + (H - T - B) * (1 - Math.min(f, maxF) / maxF);
    const s = svg('svg', { class: 'bscale-svg', viewBox: `0 0 ${W} ${H}`, width: '100%', role: 'img', 'aria-label': `HP multiplier and fight length against DPS for ${b.id}` });
    // the clamp zones
    if (cfg.enabled) {
      const lo = M.dpsForMult(cfg, ref, cfg.min), hi = M.dpsForMult(cfg, ref, cfg.max);
      const xl = Math.max(L, Math.min(W - R, xd(lo))), xh = Math.max(L, Math.min(W - R, xd(hi)));
      if (xl > L) s.appendChild(svg('rect', { x: L, y: T, width: xl - L, height: H - T - B, class: 'bs-zone' }));
      if (xh < W - R) s.appendChild(svg('rect', { x: xh, y: T, width: W - R - xh, height: H - T - B, class: 'bs-zone' }));
      if (xl > L + 30) s.appendChild(svg('text', { x: (L + xl) / 2, y: T + 12, class: 'bs-tick mid', text: 'floor' }));
      if (xh < W - R - 30) s.appendChild(svg('text', { x: (xh + W - R) / 2, y: T + 12, class: 'bs-tick mid', text: 'ceiling' }));
    }
    // the grid and the axes: a line at every doubling, labelled ×k of the reference and the DPS
    for (let e = -LO; e <= HI; e++) {
      const k = Math.pow(2, e);
      s.appendChild(svg('line', { x1: x(e), y1: T, x2: x(e), y2: H - B, class: 'bs-grid' + (e === 0 ? ' one' : '') }));
      s.appendChild(svg('text', { x: x(e), y: H - B + 14, class: 'bs-tick mid', text: k < 1 ? `×1/${Math.round(1 / k)}` : `×${k}` }));
      s.appendChild(svg('text', { x: x(e), y: H - B + 27, class: 'bs-tick mid dim', text: fmtN(ref * k, 0) }));
    }
    for (let m = 0; m <= maxM + 1e-9; m += 0.5) {
      s.appendChild(svg('line', { x1: L, y1: yM(m), x2: W - R, y2: yM(m), class: 'bs-grid' + (Math.abs(m - 1) < 1e-6 ? ' one' : '') }));
      s.appendChild(svg('text', { x: L - 6, y: yM(m) + 4, class: 'bs-tick end', text: `×${fmtN(m, 1)}` }));
    }
    for (let f = 0; f <= maxF + 1e-9; f += 0.5) s.appendChild(svg('text', { x: W - R + 6, y: yF(f) + 4, class: 'bs-tick f', text: `${Math.round(f * 100)}%` }));
    s.appendChild(svg('text', { x: (L + W - R) / 2, y: H - 4, class: 'bs-axis mid', text: 'the hero\'s DPS when the boss arrives (× the reference, and in damage a second)' }));
    s.appendChild(svg('text', { x: 10, y: 12, class: 'bs-axis m', text: 'HP ×' }));
    s.appendChild(svg('text', { x: W - 6, y: 12, class: 'bs-axis f end', text: 'fight length' }));
    // the curves: the fight without scaling (dashed), with it, the multiplier
    const path = (f) => pts.map((p, k) => `${k ? 'L' : 'M'}${x(p.e).toFixed(1)},${f(p).toFixed(1)}`).join(' ');
    s.appendChild(svg('path', { d: path((p) => yF(p.fightPlain)), class: 'bs-plain' }));
    s.appendChild(svg('path', { d: path((p) => yF(p.fight)), class: 'bs-fight' }));
    s.appendChild(svg('path', { d: path((p) => yM(p.mult)), class: 'bs-mult' }));
    s.appendChild(svg('text', { x: x(0) + 4, y: H - B - 6, class: 'bs-tick ref', text: `reference ${fmtN(ref, 0)}` }));
    // the crosshair and its readout
    const cross = svg('line', { x1: 0, y1: T, x2: 0, y2: H - B, class: 'bs-cross', visibility: 'hidden' });
    const dotM = svg('circle', { r: 4, class: 'bs-dot m', visibility: 'hidden' });
    const dotF = svg('circle', { r: 4, class: 'bs-dot f', visibility: 'hidden' });
    s.appendChild(cross); s.appendChild(dotM); s.appendChild(dotF);
    const read = el('div', { class: 'bscale-read small' });
    const say = (d) => {
      const m = M.hpMult(cfg, d, ref);
      const f = M.fightRel(cfg, d, ref), f0 = ref / d;
      const where = m <= cfg.min + 1e-9 && cfg.enabled ? ' · on the floor' : m >= cfg.max - 1e-9 && cfg.enabled ? ' · on the ceiling' : '';
      read.innerHTML = `At <b>${fmtN(d, 0)}</b> DPS (${fmtN(d / ref, 2)}× the reference): boss HP <b>×${fmtN(m, 2)}</b> = ${fmtN(base * m, 0)}; the fight <b>${fmtN(f * 100, 0)}%</b> as long as at the reference (${fmtN(f0 * 100, 0)}% without the scaling)${where}.`;
    };
    say(ref * 2);
    s.addEventListener('mousemove', (ev) => {
      const r = s.getBoundingClientRect();
      const px = (ev.clientX - r.left) * W / r.width;
      const e = Math.max(-LO, Math.min(HI, (px - L) / (W - L - R) * (LO + HI) - LO));
      const d = ref * Math.pow(2, e);
      const m = M.hpMult(cfg, d, ref);
      for (const n of [cross, dotM, dotF]) n.setAttribute('visibility', 'visible');
      cross.setAttribute('x1', x(e)); cross.setAttribute('x2', x(e));
      dotM.setAttribute('cx', x(e)); dotM.setAttribute('cy', yM(m));
      dotF.setAttribute('cx', x(e)); dotF.setAttribute('cy', yF(M.fightRel(cfg, d, ref)));
      say(d);
    });
    s.addEventListener('mouseleave', () => { for (const n of [cross, dotM, dotF]) n.setAttribute('visibility', 'hidden'); say(ref * 2); });
    box.appendChild(s);
    box.appendChild(el('div', { class: 'bscale-legend small' },
      el('span', { class: 'lg m', text: 'HP multiplier (left)' }), el('span', { class: 'lg f', text: 'fight length with the scaling (right)' }),
      el('span', { class: 'lg p', text: 'without it' }), cfg.enabled ? el('span', { class: 'lg z', text: 'floor / ceiling holds' }) : el('span', { class: 'lg off', text: 'scaling is OFF: every boss keeps ×1' })));
    box.appendChild(read);
    box.appendChild(el('div', { class: 'muted small', text: `HP at ×1: ${fmtN(base, 0)} (stage ${b.stage + 1}: hp × hp_mult_per_stage^stage × the stage multiplier). The fight's length is against the fight a hero at the reference has (100%): the boss's HP over the DPS, the crowd taking the same share of it at any DPS. Each step right doubles the DPS.` }));
    return box;
  }

  return { block, WORDS };
})();
