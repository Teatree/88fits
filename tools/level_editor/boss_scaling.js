'use strict';
// Pass 72 (lane BOSS): the Settings tab's "Boss HP" card below the numbers fields.js lists (boss_hp_scaling.*): the
// reference DPS of every boss the timeline brings, a chart of the HP multiplier and the fight's length against the hero's
// DPS, and the thinking in plain words. The maths are boss_model.js (the game's WaveTimeline.boss_hp_mult).
// Pass 83 (lane SCALE; Garry: "Fix the Boss HP. I want it to take at least 25 seconds of Player's FULL DPS on Tumbleweed
// king to kill it. Then 40s for the next and a full minute to the last one ... Assume which parts confused me and fix
// them with extra explanations (hints)"): a "How it works" box on top (the rule in one sentence, a worked example on the
// first boss, what went wrong with the old references), the seconds mode's rows (one a boss) and its chart (boss HP
// against the hero's full DPS); pass 72's references and chart only in the pegged mode.
const BossScaling = (() => {
  const { el, svg, fmtN, fmtT } = U;
  const M = BossModel;
  let chosen = null;          // the boss the chart shows (an id), kept across redraws

  // the pegged mode's thinking (pass 72), shown when that mode is picked
  const WORDS = [
    'Why: a strong build melts a boss in seconds, a weak one is stuck with it for minutes. When a boss arrives the game reads the hero\'s damage a second over the last <b>window</b> seconds (what his hits really took off creatures, the same numbers as the Results screen) and gives the boss <b>(his DPS ÷ the boss\'s reference DPS) ^ exponent</b> times its HP, held between the floor and the ceiling.',
    'Why not 1 to 1: if the HP grew as fast as the DPS, every fight would last the same and a stronger build would be worth nothing against a boss. With the exponent <b>0.5</b> the HP grows with the square root of the DPS: <b>twice</b> the reference DPS gives the boss 1.41 times its HP and the fight is still <b>29% shorter</b>; four times: twice the HP, the fight half as long. Exponent 0 = never scaled, 1 = every fight as long as at the reference.',
    'The <b>floor</b> (0.75) gives a weak build a softer boss but never a pushover; the <b>ceiling</b> (3×) keeps a monster build from a sponge. The <b>references</b> are the DPS of the builds the difficulty was tuned on (tools/difficulty_probe.gd before each boss: Calavera and Drifter, the stage\'s build and Upgrade board): a hero at the reference meets the boss exactly as before. The debug arena never scales.',
    'A caution: the DPS counts only what a hit took off (a 500 hit on a 20 HP goblin is 20), so when the crowd dies faster than it comes, the DPS shows the crowd more than the build. In endless a returning boss\'s reference grows with its own HP growth since its stage.',
  ];
  // pass 83: the seconds mode's thinking
  const SECONDS_WORDS = [
    '<b>Full DPS</b> is the hero\'s damage a second on ONE target that every shot hits, read the moment the boss arrives: every weapon\'s pause-screen "dps" with its crowd guess taken out, its burn or poison kept up, times his average crit, and Big Game Hunter\'s bonus on bosses (the Hero power card below spells it out). It is a ceiling: nobody lands every shot.',
    'So the seconds are a <b>least</b>: "25" means even a perfect player who never misses needs 25 seconds on the King. Measured on a boss held still in front of the hero (game/tools/_p83_SCALE_boss_probe.gd), the kills took 1.1 to 2.3 times the seconds (4 times for a Salt build, whose patches the boss must walk into): some weapons miss a big body (the Tommy Gun\'s scattered rounds), orbits and blades reach it only close up, the Salt only where it walks. A real fight is longer again: he dodges, kites, its minions take shots.',
    'The boss never comes with less than its own data HP (its hp × hp_mult_per_stage per stage × the stage multiplier): a weak hero meets the boss as it was before any scaling. Crits and burns are in the full DPS already; the boss\'s own damage reduction is folded in (the HP is the full DPS × the seconds × (1 − its reduction)), so armour does not lengthen the fight. Elites and a boss spawned by hand or in the debug arena are never scaled. In endless a returning boss takes the same seconds of the DPS the hero has then.',
  ];

  /** The card's own block (after fields.js's rows): the "how it works" box, the mode's own rows and chart, the words. */
  function block(tl) {
    const wrap = el('div', { class: 'bscale' });
    const cfg = M.scalingOf(tl);
    const mode = M.modeOf(tl);
    const bosses = M.bossEvents(tl);
    wrap.appendChild(howBox(tl, cfg, mode, bosses));
    if (!cfg.enabled) return wrap;
    wrap.appendChild(mode === 'seconds' ? secondsBlock(tl, bosses) : peggedBlock(tl, cfg, bosses));
    const words = el('details', { class: 'bscale-words', open: true }, el('summary', { text: mode === 'seconds' ? 'Seconds of full DPS: what it means, and what it does not' : 'How the pegged mode works, and why' }));
    for (const w of (mode === 'seconds' ? SECONDS_WORDS : WORDS)) { const p = el('p', { class: 'small' }); p.innerHTML = w; words.appendChild(p); }
    wrap.appendChild(words);
    return wrap;
  }

  /** Pass 83: the box at the top of the card: the rule picked in one sentence, a worked example on the first boss, and
   *  what most likely went wrong with the numbers before (references far above the measured ones made the bosses softer). */
  function howBox(tl, cfg, mode, bosses) {
    const box = el('div', { class: 'bscale-how' });
    const b0 = bosses[0];
    const c0 = b0 ? App.creature(b0.id) : null;
    const name0 = c0 ? c0.name : (b0 ? b0.id : 'the first boss');
    const base0 = b0 ? M.bossBaseHp(c0, tl, b0.stage) : 0;
    const p = (html) => { const n = el('p', { class: 'small' }); n.innerHTML = html; box.appendChild(n); };
    box.appendChild(el('h3', { class: 'block-title', text: 'How it works' }));
    if (!cfg.enabled) { p('Scaling is <b>off</b>: each boss has the HP its JSON gives it (hp × hp_mult_per_stage per stage × the stage multiplier), whatever the hero deals.'); return box; }
    const bhs = tl && tl.boss_hp_scaling && typeof tl.boss_hp_scaling === 'object' ? tl.boss_hp_scaling : {};
    const refs = bhs.ref_dps && typeof bhs.ref_dps === 'object' ? bhs.ref_dps : {};
    if (mode === 'seconds') {
      const secs = M.num(M.secondsOf(tl)[b0 ? b0.id : ''], 0);
      const dps = 300;
      p('When a boss arrives, its HP = <b>the hero\'s full DPS at that moment × the boss\'s seconds</b> (the rows below), never less than its own data HP. More seconds = a tougher boss. Full DPS = every weapon\'s damage a second on one target that every shot hits (the Hero power card spells it out).');
      if (b0 && secs > 0) p(`Example, ${name0} (${fmtT(b0.t)}): its data HP is <b>${fmtN(base0, 0)}</b>. A hero with <b>${dps}</b> full DPS faces ${name0} with ${dps} × ${secs} = <b>${fmtN(Math.max(base0, dps * secs), 0)} HP</b>: ${secs} seconds if every one of his shots lands on it, longer in a real fight. A hero with ${fmtN(base0 / secs, 0)} full DPS or less meets its data HP.`);
      const odd = bosses.filter((b) => M.num(refs[b.id], 0) > 0);
      if (odd.length) p(`The <b>reference DPS</b> numbers this map still has (${odd.map((b) => fmtN(refs[b.id], 0)).join(' / ')}) belong to the pegged mode and do nothing now. Why the King went down in seconds before: in the pegged mode a <b>bigger reference makes the boss softer</b> (its HP × (the hero's DPS ÷ the reference) ^ 0.5); a hero dealing about ${fmtN(M.REF_DEFAULTS.tumbleweed_king || 600, 0)} real DPS at 7:10 against a reference of ${fmtN(M.num(refs.tumbleweed_king, 0), 0)} got the floor, ×0.75 of the data HP.`);
    } else {
      p('When a boss arrives, its data HP is multiplied by <b>(the hero\'s real DPS over the last window ÷ the boss\'s reference DPS) ^ exponent</b>, held between the floor and the ceiling. The reference is the DPS at which a boss keeps its data HP (×1), so a <b>bigger reference makes the boss softer</b>.');
      const ref = M.num(cfg.ref[b0 ? b0.id : ''], 0);
      if (b0 && ref > 0) {
        const d = 600, m = M.hpMult(cfg, d, ref);
        p(`Example, ${name0}: data HP <b>${fmtN(base0, 0)}</b>, reference ${fmtN(ref, 0)}. A hero dealing ${d} real DPS gets ×${fmtN(m, 2)} = <b>${fmtN(base0 * m, 0)} HP</b>, about ${fmtN(base0 * m / d, 0)} s if all of his damage went into the boss.`);
      }
    }
    return box;
  }

  /** Pass 83: the seconds mode's rows (one a boss: its seconds, its data HP, the HP a tuned build meets) and the chart. */
  function secondsBlock(tl, bosses) {
    const wrap = el('div', { class: 'bscale-refs' });
    const secs = M.secondsOf(tl);
    wrap.appendChild(el('h3', { class: 'block-title', text: 'Seconds of full DPS (each boss)' }));
    for (const b of bosses) {
      const creature = App.creature(b.id) || null;
      const gdef = M.SECONDS_DEFAULTS[b.id];
      const def = { key: `boss_hp_scaling.seconds.${b.id}`, label: `${creature ? creature.name : b.id} · ${fmtT(b.t)}`, type: 'number', min: 0, step: 5, def: gdef,
        help: `How many seconds ${creature ? creature.name : b.id} lasts against the hero's full DPS (every shot landing): its HP = his full DPS when it arrives × this, never less than its data HP. 0 = it keeps its data HP; empty = ${gdef ? 'the game\'s ' + gdef + ' s' : 'its data HP (the game has no seconds for it)'}.` };
      const base = M.bossBaseHp(creature, tl, b.stage);
      const s = M.num(secs[b.id], 0);
      const typ = M.TYPICAL_FULL_DPS[b.id];
      const note = s > 0 ? `data HP ${fmtN(base, 0)} · more from ${fmtN(M.secondsCross(base, s), 0)} full DPS${typ ? ` · a tuned build (${fmtN(typ, 0)} full DPS): ${fmtN(M.secondsHp(base, typ, s, 0), 0)} HP` : ''}` : `data HP ${fmtN(base, 0)} (never scaled)`;
      wrap.appendChild(Forms.fieldRow(def, tl, { after: el('span', { class: 'muted small', text: ' ' + note }) }));
    }
    if (!bosses.length) wrap.appendChild(el('p', { class: 'muted small', text: 'The timeline brings no boss event.' }));
    if (!chosen || !bosses.some((b) => b.id === chosen)) chosen = (bosses[0] || {}).id || null;
    const pick = el('div', { class: 'bscale-pick' }, el('span', { class: 'muted small', text: 'Chart for ' }));
    for (const b of bosses) {
      const c = App.creature(b.id);
      pick.appendChild(el('button', { class: 'btn small' + (b.id === chosen ? ' primary' : ''), type: 'button', text: c ? c.name : b.id, onclick: () => { chosen = b.id; App.render('tab'); } }));
    }
    wrap.appendChild(pick);
    const b = bosses.find((x) => x.id === chosen);
    if (b) wrap.appendChild(secondsChart(tl, b, M.num(secs[b.id], 0)));
    return wrap;
  }

  /** Pass 83: boss HP against the hero's full DPS when it arrives (linear, 0 to twice a tuned build's): its data HP
   *  (dashed), the HP the seconds give (solid, never under the data HP), a tuned build marked; a crosshair reads it. */
  function secondsChart(tl, b, secs) {
    const creature = App.creature(b.id);
    const base = M.bossBaseHp(creature, tl, b.stage);
    const box = el('div', { class: 'bscale-chart' });
    if (!(secs > 0)) { box.appendChild(el('p', { class: 'muted small', text: `${b.id} has 0 seconds: it keeps its data HP whatever the hero deals.` })); return box; }
    const typ = M.TYPICAL_FULL_DPS[b.id] || Math.max(M.secondsCross(base, secs) * 4, 100);
    const xMax = Math.max(typ * 2, M.secondsCross(base, secs) * 2);
    const yMax = Math.max(M.secondsHp(base, xMax, secs, 0), base) * 1.08;
    const W = 500, H = 240, L = 58, R = 16, T = 18, B = 46;
    const x = (d) => L + (W - L - R) * d / xMax;
    const y = (h) => T + (H - T - B) * (1 - h / yMax);
    const s = svg('svg', { class: 'bscale-svg', viewBox: `0 0 ${W} ${H}`, width: '100%', role: 'img', 'aria-label': `HP against full DPS for ${b.id}` });
    const nice = (v) => { const q = Math.pow(10, Math.floor(Math.log10(Math.max(v, 1)))); const m = v / q; return (m <= 1 ? 1 : m <= 2 ? 2 : m <= 5 ? 5 : 10) * q; };
    const xs = nice(xMax / 6), ys = nice(yMax / 5);
    for (let d = 0; d <= xMax + 1e-9; d += xs) {
      s.appendChild(svg('line', { x1: x(d), y1: T, x2: x(d), y2: H - B, class: 'bs-grid' }));
      s.appendChild(svg('text', { x: x(d), y: H - B + 14, class: 'bs-tick mid', text: fmtN(d, 0) }));
    }
    for (let h = 0; h <= yMax + 1e-9; h += ys) {
      s.appendChild(svg('line', { x1: L, y1: y(h), x2: W - R, y2: y(h), class: 'bs-grid' }));
      s.appendChild(svg('text', { x: L - 6, y: y(h) + 4, class: 'bs-tick end', text: fmtN(h, 0) }));
    }
    s.appendChild(svg('text', { x: (L + W - R) / 2, y: H - 14, class: 'bs-axis mid', text: 'the hero\'s FULL DPS when the boss arrives (every shot landing on it)' }));
    s.appendChild(svg('text', { x: 10, y: 12, class: 'bs-axis m', text: 'boss HP' }));
    s.appendChild(svg('line', { x1: x(0), y1: y(base), x2: x(xMax), y2: y(base), class: 'bs-plain' }));
    const N = 60;
    let dd = '';
    for (let k = 0; k <= N; k++) { const d = xMax * k / N; dd += `${k ? 'L' : 'M'}${x(d).toFixed(1)},${y(M.secondsHp(base, d, secs, 0)).toFixed(1)}`; }
    s.appendChild(svg('path', { d: dd, class: 'bs-mult' }));
    if (M.TYPICAL_FULL_DPS[b.id]) {
      s.appendChild(svg('line', { x1: x(typ), y1: T, x2: x(typ), y2: H - B, class: 'bs-ref' }));
      s.appendChild(svg('text', { x: x(typ) + 4, y: T + 10, class: 'bs-tick ref', text: `a tuned build: ${fmtN(typ, 0)}` }));
    }
    const cross = svg('line', { x1: 0, y1: T, x2: 0, y2: H - B, class: 'bs-cross', visibility: 'hidden' });
    const dot = svg('circle', { r: 4, class: 'bs-dot m', visibility: 'hidden' });
    s.appendChild(cross); s.appendChild(dot);
    const read = el('div', { class: 'bscale-read small' });
    const say = (d) => {
      const h = M.secondsHp(base, d, secs, 0);
      read.innerHTML = h <= base + 1e-6
        ? `At <b>${fmtN(d, 0)}</b> full DPS the boss keeps its data HP <b>${fmtN(base, 0)}</b> (${secs} s of his full DPS would be only ${fmtN(d * secs, 0)}): ${fmtN(base / Math.max(d, 1), 0)} s if every shot lands.`
        : `At <b>${fmtN(d, 0)}</b> full DPS: boss HP <b>${fmtN(h, 0)}</b> = ${fmtN(d, 0)} × ${secs} s, so at least <b>${secs} s</b> even if every shot lands (its data HP ${fmtN(base, 0)} alone would last ${fmtN(base / d, 1)} s).`;
    };
    say(typ);
    s.addEventListener('mousemove', (ev) => {
      const r = s.getBoundingClientRect();
      const px = (ev.clientX - r.left) * W / r.width;
      const d = Math.max(1, Math.min(xMax, (px - L) / (W - L - R) * xMax));
      for (const n of [cross, dot]) n.setAttribute('visibility', 'visible');
      cross.setAttribute('x1', x(d)); cross.setAttribute('x2', x(d));
      dot.setAttribute('cx', x(d)); dot.setAttribute('cy', y(M.secondsHp(base, d, secs, 0)));
      say(d);
    });
    s.addEventListener('mouseleave', () => { for (const n of [cross, dot]) n.setAttribute('visibility', 'hidden'); say(typ); });
    box.appendChild(s);
    box.appendChild(el('div', { class: 'bscale-legend small' }, el('span', { class: 'lg m', text: 'the HP it comes with' }), el('span', { class: 'lg p', text: 'its data HP (the least)' })));
    box.appendChild(read);
    box.appendChild(el('div', { class: 'muted small', text: `Data HP ${fmtN(base, 0)}: stage ${b.stage + 1}, hp × hp_mult_per_stage^stage × the stage multiplier. "A tuned build": the full DPS the probe's builds (Calavera, the Drifter, Jeżyk, Fadeaway on difficulty_probe's b1 / b2 / b3) have when this boss arrives (pass 83).` }));
    return box;
  }

  /** Pass 72's block for the pegged mode: the references, one row a boss, and the chart. */
  function peggedBlock(tl, cfg, bosses) {
    const wrap = el('div', {});
    if (!cfg.present) wrap.appendChild(el('p', { class: 'muted small', text: 'This map has no boss_hp_scaling block: it plays the game\'s defaults (the grey numbers: the measured reference DPS of each boss).' }));
    const refs = el('div', { class: 'bscale-refs' });
    refs.appendChild(el('h3', { class: 'block-title', text: 'Reference DPS (the real DPS at which a boss keeps its data HP: bigger = softer boss)' }));
    for (const b of bosses) {
      const creature = App.creature(b.id) || null;
      const gdef = M.REF_DEFAULTS[b.id];
      const def = { key: `boss_hp_scaling.ref_dps.${b.id}`, label: `${creature ? creature.name : b.id} · ${fmtT(b.t)}`, type: 'number', min: 0, step: 50, def: gdef,
        help: `${b.id}'s reference DPS: the hero's real damage a second over the window at which it keeps its data HP (×1). A hero above it meets a tougher boss, below it a softer one (down to the floor), so a BIGGER reference makes the boss SOFTER. 0 = this boss is never scaled; empty = ${gdef ? 'the game\'s ' + gdef + ' (measured: what a tuned build really deals before it)' : 'never scaled (the game has no reference for it)'}. Measured with tools/difficulty_probe.gd (the DPS45 line) over the 45 s before ${fmtT(b.t)}.` };
      const base = M.bossBaseHp(creature, tl, b.stage);
      const ref = M.num(cfg.ref[b.id], 0);
      const note = ref > 0 ? `HP ${fmtN(base, 0)} at ×1 · at 2× this DPS: ${fmtN(base * M.hpMult(cfg, ref * 2, ref), 0)}` : 'never scaled';
      refs.appendChild(Forms.fieldRow(def, tl, { after: el('span', { class: 'muted small', text: ' ' + note }) }));
    }
    if (!bosses.length) refs.appendChild(el('p', { class: 'muted small', text: 'The timeline brings no boss event.' }));
    wrap.appendChild(refs);
    if (!chosen || !bosses.some((b) => b.id === chosen)) chosen = (bosses.find((b) => M.num(cfg.ref[b.id], 0) > 0) || bosses[0] || {}).id || null;
    const pick = el('div', { class: 'bscale-pick' }, el('span', { class: 'muted small', text: 'Chart for ' }));
    for (const b of bosses) {
      const c = App.creature(b.id);
      pick.appendChild(el('button', { class: 'btn small' + (b.id === chosen ? ' primary' : ''), type: 'button', text: c ? c.name : b.id, onclick: () => { chosen = b.id; App.render('tab'); } }));
    }
    wrap.appendChild(pick);
    const b = bosses.find((x) => x.id === chosen);
    if (b) wrap.appendChild(chart(tl, cfg, b));
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

  return { block, WORDS, SECONDS_WORDS };
})();
