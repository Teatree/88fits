'use strict';
// Pass 83 (lane SCALE): the Settings tab's "Hero power" card under its two rows (fields.js power_hp_scaling, power_hp_max):
// how the hero's power level is calculated (the reminder Garry asked for: "You will add this power calculation reminder
// in the Level Editor so I can find it easily"), a chart of the creatures' HP multiplier against the power for the value
// set, and where the power is charted. The maths are power_model.js (the game's HeroPower.gd, WaveTimeline.power_hp_factor).
const PowerCard = (() => {
  const { el, svg, fmtN } = U;
  const P = PowerModel;

  const HOW = [
    '<b>Power = √( (full DPS ÷ 20.4) × (effective HP ÷ 100) )</b>. A fresh level-1 Drifter with the Revolver on a clean save is <b>1.0</b>. It is the average (geometric mean) of how hard he hits and how much he can take, each against that fresh Drifter: twice the DPS alone makes 1.41, twice the DPS and twice the HP makes 2.',
    '<b>Full DPS</b> = what all his weapons deal a second to ONE target that every shot hits: each weapon\'s pause-screen "dps" with its crowd guess taken out (a smash, a cone wave or a gravity blast counts 3 creatures a blow there, a mine or a laser 2, a sun pillar 1.6, a frisbee 2.6, a chained beam 1 + its chains, a gun\'s blast its catch), plus its burn or poison kept up, times his average crit (1 + crit chance × (crit damage − 1)). The same full DPS sets the bosses\' HP (Boss HP card, "seconds of full DPS").',
    '<b>Effective HP</b> = (max HP + shield + 30 seconds of regen and lifesteal) ÷ ((1 − armour) × (1 − evade)): the damage the creatures must deal to bring him down over a 30-second fight.',
    'Why the square root: the time a fight against him lasts grows with his DPS × his HP; the root keeps the number readable (about 1 at the start, 3 to 5 at the King, 6 to 24 at the Gila, 14 to 50 at the Brander on the probe\'s tuned builds).',
    'Where to see it: the run dashboard (analytics/dashboard.html: "Hero power", one run and averages, the players\' Remote runs too), the Sim tab\'s charts, and the Watch (the "Power" button over its first chart, or P). Every run record carries it each second (power, full_dps, ehp; analytics/SCHEMA.md).',
  ];

  /** The card's own block (after fields.js's two rows): the chart, the words. */
  function block(tl) {
    const wrap = el('div', { class: 'bscale pcard' });
    const cfg = P.scalingOf(tl);
    const how = el('details', { class: 'bscale-words', open: true }, el('summary', { text: 'How power is calculated' }));
    for (const w of HOW) { const p = el('p', { class: 'small' }); p.innerHTML = w; how.appendChild(p); }
    wrap.appendChild(how);
    wrap.appendChild(chart(cfg));
    return wrap;
  }

  /** x = the hero's power on a doubling scale (1 to 64), y = the creatures' HP multiplier for the value set; the tuned
   *  builds' power at each boss marked; a crosshair reads any power. */
  function chart(cfg) {
    const box = el('div', { class: 'bscale-chart' });
    const HI = 64, W = 500, H = 220, L = 48, R = 16, T = 18, B = 46;
    const pts = P.series(cfg.scaling, cfg.max, HI, 160);
    const top = Math.max(2, ...pts.map((q) => q.f)) * 1.1;
    const bot = Math.min(1, ...pts.map((q) => q.f));
    const lo = bot < 1 ? 0 : 0;
    const x = (p) => L + (W - L - R) * Math.log2(Math.max(p, 1)) / Math.log2(HI);
    const y = (f) => T + (H - T - B) * (1 - (f - lo) / (top - lo));
    const s = svg('svg', { class: 'bscale-svg', viewBox: `0 0 ${W} ${H}`, width: '100%', role: 'img', 'aria-label': 'creature HP multiplier against the hero power' });
    for (let e = 0; e <= 6; e++) {
      const p = Math.pow(2, e);
      s.appendChild(svg('line', { x1: x(p), y1: T, x2: x(p), y2: H - B, class: 'bs-grid' + (e === 0 ? ' one' : '') }));
      s.appendChild(svg('text', { x: x(p), y: H - B + 14, class: 'bs-tick mid', text: String(p) }));
    }
    const step = top > 8 ? 2 : top > 4 ? 1 : 0.5;
    for (let f = 0; f <= top + 1e-9; f += step) {
      s.appendChild(svg('line', { x1: L, y1: y(f), x2: W - R, y2: y(f), class: 'bs-grid' + (Math.abs(f - 1) < 1e-6 ? ' one' : '') }));
      s.appendChild(svg('text', { x: L - 6, y: y(f) + 4, class: 'bs-tick end', text: `×${fmtN(f, 1)}` }));
    }
    for (const m of P.TYPICAL) {
      s.appendChild(svg('line', { x1: x(m.power), y1: T, x2: x(m.power), y2: H - B, class: 'bs-ref' }));
      s.appendChild(svg('text', { x: x(m.power) + 3, y: T + 10, class: 'bs-tick ref', text: m.at }));
    }
    s.appendChild(svg('text', { x: (L + W - R) / 2, y: H - 14, class: 'bs-axis mid', text: 'the hero\'s power (fresh level-1 Drifter = 1; each step right doubles it)' }));
    s.appendChild(svg('text', { x: 10, y: 12, class: 'bs-axis m', text: 'creature HP ×' }));
    const path = pts.map((q, k) => `${k ? 'L' : 'M'}${x(q.p).toFixed(1)},${y(q.f).toFixed(1)}`).join(' ');
    s.appendChild(svg('path', { d: path, class: 'bs-mult' }));
    const cross = svg('line', { x1: 0, y1: T, x2: 0, y2: H - B, class: 'bs-cross', visibility: 'hidden' });
    const dot = svg('circle', { r: 4, class: 'bs-dot m', visibility: 'hidden' });
    s.appendChild(cross); s.appendChild(dot);
    const read = el('div', { class: 'bscale-read small' });
    const say = (p) => {
      const f = P.hpFactor(cfg.scaling, cfg.max, p);
      read.innerHTML = Math.abs(cfg.scaling - 1) < 1e-6
        ? `Scaling <b>1</b>: no scaling at all; every creature keeps its HP at any power (at power ${fmtN(p, 1)}: ×1).`
        : `At power <b>${fmtN(p, 1)}</b>: every ordinary creature spawns with <b>×${fmtN(f, 2)}</b> HP (power ${fmtN(p, 1)} ^ (${fmtN(cfg.scaling, 2)} − 1)${f >= cfg.max - 1e-9 ? ', held at the cap' : ''}). A 100-HP goblin: ${fmtN(100 * f, 0)} HP.`;
    };
    say(8);
    s.addEventListener('mousemove', (ev) => {
      const r = s.getBoundingClientRect();
      const px = (ev.clientX - r.left) * W / r.width;
      const p = Math.pow(2, Math.max(0, Math.min(Math.log2(HI), (px - L) / (W - L - R) * Math.log2(HI))));
      for (const n of [cross, dot]) n.setAttribute('visibility', 'visible');
      cross.setAttribute('x1', x(p)); cross.setAttribute('x2', x(p));
      dot.setAttribute('cx', x(p)); dot.setAttribute('cy', y(P.hpFactor(cfg.scaling, cfg.max, p)));
      say(p);
    });
    s.addEventListener('mouseleave', () => { for (const n of [cross, dot]) n.setAttribute('visibility', 'hidden'); say(8); });
    box.appendChild(s);
    box.appendChild(el('div', { class: 'bscale-legend small' }, el('span', { class: 'lg m', text: `creature HP × at scaling ${fmtN(cfg.scaling, 2)}` }),
      el('span', { class: 'lg', text: 'dashed: the power of the probe\'s tuned builds when each boss arrives' })));
    box.appendChild(read);
    return box;
  }

  /** The Instructions tab's section (pass 83): where the boss HP and the power live, how to set them up, the formula. */
  function instructions(root) {
    const p = (html) => { const n = el('p', {}); n.innerHTML = html; return n; };
    const li = (html) => { const n = el('li', {}); n.innerHTML = html; return n; };
    root.appendChild(el('h2', { text: 'Pass 83: boss HP by seconds of full DPS, and the hero\'s power' }));
    root.appendChild(p('Garry: <i>"I want it to take at least 25 seconds of Player\'s FULL DPS on Tumbleweed king to kill it. Then 40s for the next and a full minute to the last one"</i> and <i>"add a modifier for the enemy HP scaling with the power level of the Player ... Default scaling is 1, meaning no scaling at all."</i>'));
    root.appendChild(el('ul', {},
      li('<b>Boss HP</b>: Settings → <b>Boss HP</b>. "Boss HP is set by" = <b>seconds of full DPS</b> (the default). Each boss has a row of seconds (King 25, Gila 40, Brander 60): when it arrives its HP = the hero\'s full DPS then × its seconds, never less than its data HP. Raise a boss\'s seconds to make it tougher. The "How it works" box at the top of the card works one example through; the chart shows the HP for any full DPS (hover it).'),
      li('<b>What "full DPS" is</b>: every weapon\'s damage a second on one target that every shot hits (the pause screen\'s numbers without their crowd guess, burns and crits in). Nobody lands every shot, so a real fight lasts longer than the seconds: they are a least, not an exact length.'),
      li('<b>The old numbers</b> (exponent, window, floor, ceiling, the reference DPS) belong to the other choice, "pegged to recent DPS" (pass 72), and only show when it is picked. There a bigger reference made a boss <b>softer</b>: that is why the King died in seconds with references of 6,000 / 45,000 / 200,000.'),
      li('<b>The hero\'s power</b>: Settings → <b>Hero power</b>, the "How power is calculated" box. Power = √((full DPS ÷ 20.4) × (effective HP ÷ 100)); a fresh level-1 Drifter is 1. Charted every second in the run dashboard, the Sim tab and the Watch (its Power button, or P).'),
      li('<b>Enemy HP by power</b>: Settings → Hero power → "Enemy HP by power". 1 = no scaling (the default). 2 = creature HP grows in step with the power, 1.5 with its square root, below 1 softer. The chart under it shows the multiplier at any power; "Most HP × by power" caps it. Bosses and Elites by their kind are never touched; a row reads the power when it first spawns and keeps it.')));
  }

  return { block, HOW, instructions };
})();
