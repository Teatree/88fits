'use strict';
// Pass 82 (lane XP; Garry: "EXP requirements - I feel like we don't have enough settings for EXP requirements. Say I want
// to make the EXP requirements exponential instead of linear, it doesn't look like I can. I want that section to include
// types of EXP growth displayed in a dropdown, each one with it's own 2 charts for cumulative and per level EXP
// requirements"): the Settings tab's "XP per level" card. The Growth dropdown (xp_curve.type), the chosen type's numbers
// (each box shows the game's default, greyed, until it is set), XP needed ×, the page's checks, two charts for the chosen
// type (the XP each level needs, the XP reaching a level takes in all; levels 1-30/60/100, a log scale, today's curve as
// a faint dashed line, one crosshair over both), a table of the stage levels, and the levels the latest sim's XP reaches
// at what minute. Numbers typed but not committed redraw the charts at once (a preview); a change (Enter, leaving the
// box) is one undo step. The maths are xp_model.js (the game's game/core/data/XpCurve.gd); the rows are fields.js'
// XP_TYPES.
const XpCard = (() => {
  const { el, svg, fmtT } = U;
  const M = XpModel;
  const RANGES = [30, 60, 100];
  const LS = '88fits-xp-card';
  const TODAY = {};   // the curve every run played before pass 82 (no xp_curve)
  const view = { range: 60, log: false };
  try { const v = JSON.parse(localStorage.getItem(LS) || 'null'); if (v) { if (RANGES.includes(v.range)) view.range = v.range; view.log = !!v.log; } } catch (_) { /* defaults */ }
  const saveView = () => { try { localStorage.setItem(LS, JSON.stringify(view)); } catch (_) { /* fine */ } };

  // the latest sim's XP a second (fetched once a page load; "Refresh" fetches again)
  const sim = { state: 'idle', id: '', label: '', xp: null, err: '', T: 0 };
  let simBox = null;          // the line under the charts on the card drawn last
  let lastDraw = null;        // that card's (curve, mult) as committed, for the sim line

  // ------------------------------------------------------------------ numbers

  /** "1,234", "56.5", "0.01" */
  function fmtXp(x) {
    if (x == null || !isFinite(x)) return '–';
    if (Math.abs(x) >= 1000) return Math.round(x).toLocaleString('en-US');
    if (Math.abs(x) >= 10) return String(Math.round(x * 10) / 10);
    return String(Math.round(x * 100) / 100);
  }

  /** An axis label: 950, 1.5k, 20k, 3.2M */
  function fmtK(x) {
    const a = Math.abs(x);
    const cut = (v, s) => (Math.round(v * 10) / 10).toString().replace(/\.0$/, '') + s;
    if (a >= 1e9) return cut(x / 1e9, 'B');
    if (a >= 1e6) return cut(x / 1e6, 'M');
    if (a >= 1e3) return cut(x / 1e3, 'k');
    return String(Math.round(x));
  }

  /** Ticks for a linear axis from 0: [values], the top. */
  function linTicks(max, n) {
    if (!(max > 0)) return { ticks: [0, 1], top: 1 };
    const raw = max / n;
    const p = Math.pow(10, Math.floor(Math.log10(raw)));
    const m = raw / p;
    const step = (m <= 1 ? 1 : m <= 2 ? 2 : m <= 2.5 ? 2.5 : m <= 5 ? 5 : 10) * p;
    const top = Math.ceil(max / step - 1e-9) * step;
    const ticks = [];
    for (let v = 0; v <= top + step * 1e-6; v += step) ticks.push(v);
    return { ticks, top };
  }

  /** Ticks for a log axis: the powers of ten round [min, max]. */
  function logTicks(min, max) {
    const lo = Math.floor(Math.log10(Math.max(min, 1e-3)));
    let hi = Math.ceil(Math.log10(Math.max(max, 1e-3)));
    if (hi <= lo) hi = lo + 1;
    const ticks = [];
    for (let e = lo; e <= hi; e++) ticks.push(Math.pow(10, e));
    return { ticks, lo: Math.pow(10, lo), hi: Math.pow(10, hi) };
  }

  const esc = (t) => String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const same = (a, b) => a.length === b.length && a.every((p, k) => Math.abs(p.need - b[k].need) <= 1e-9 * Math.max(1, p.need));

  // ------------------------------------------------------------------ writing the map

  function ensure(d) { if (!U.isObj(d.xp_curve)) d.xp_curve = {}; return d.xp_curve; }
  /** No block left, or only `type: quadratic` with nothing else: the key goes (absent = today's curve). */
  function tidy(d) {
    const c = d.xp_curve;
    if (!U.isObj(c)) return;
    const keys = Object.keys(c);
    if (!keys.length || (keys.length === 1 && c.type === 'quadratic')) delete d.xp_curve;
  }
  const setType = (v) => App.apply((d) => { ensure(d).type = v || 'quadratic'; tidy(d); });
  const setParam = (ty, key, v) => App.apply((d) => {
    const c = ensure(d);
    if (c.type == null && ty !== 'quadratic') c.type = ty;
    U.setPath(c, `${ty}.${key}`, v);
    tidy(d);
  });
  const setPoints = (pts) => App.apply((d) => {
    const c = ensure(d);
    if (c.type == null) c.type = 'table';
    if (!U.isObj(c.table)) c.table = {};
    if (pts == null) delete c.table.points;
    else c.table.points = pts.slice().sort((a, b) => (Number(a[0]) || 0) - (Number(b[0]) || 0));
    if (!Object.keys(c.table).length) delete c.table;
    tidy(d);
  });

  // ------------------------------------------------------------------ the card

  /** The card's body (settings.js puts it in the "XP per level" card in place of fields.js' xp_curve rows). */
  function block(tl) {
    const wrap = el('div', { class: 'xpc' });
    const c = M.curveOf(tl);
    const ty = M.typeOf(c);
    const meta = FIELDS.XP_TYPES.find((t) => t.v === ty) || FIELDS.XP_TYPES[0];
    const own = U.isObj(c[ty]) ? c[ty] : {};
    const mult0 = M.multOf(tl);
    // what the charts draw while a box is being typed in (committed on change)
    const temp = { curve: null, mult: null };
    const curveNow = () => temp.curve || c;
    const multNow = () => (temp.mult != null ? temp.mult : mult0);
    let redraw = () => {};
    const preview = (fn) => { const cc = JSON.parse(JSON.stringify(c)); if (!U.isObj(cc[ty])) cc[ty] = {}; if (cc.type == null) cc.type = ty; fn(cc); temp.curve = cc; redraw(); };

    // the dropdown
    const typeDef = FIELDS.SCALARS.find((d) => d.key === 'xp_curve.type');
    wrap.appendChild(Forms.row(typeDef, Forms.select(typeDef.options, ty, setType, { path: 'xp_curve.type' })));
    const formula = el('div', { class: 'xpc-formula' },
      el('span', { class: 'xpc-f-label', text: 'XP level L needs =' }), el('code', { text: `(${meta.formula}) × XP needed ×` }));
    wrap.appendChild(formula);
    wrap.appendChild(el('p', { class: 'muted small xpc-help', text: meta.help + '.' }));
    if (!U.isObj(tl.xp_curve)) wrap.appendChild(el('p', { class: 'muted small', text: 'This map names no growth type: it plays today\'s curve, exactly as every run before. Pick a type to change it (Undo takes it back).' }));

    // the type's numbers (an empty box shows the game's default in grey; typing it back, or emptying the box, inherits again)
    const params = el('div', { class: 'xpc-params' });
    for (const p of meta.params) {
      const key = `xp_curve.${ty}.${p.key}`;
      const def = FIELDS.SCALARS.find((d) => d.key === key) || Object.assign({ key }, p);
      const gameDef = M.DEFAULTS[ty][p.key];
      if (p.type === 'xp_points') { params.appendChild(Forms.row(Object.assign({}, def, { help: p.help, label: p.label }), pointsBlock(own.points, gameDef, preview), { cls: 'wide-ctl' })); continue; }
      let ctl;
      if (p.type === 'percent') {
        ctl = Forms.percentInput(def, own[p.key], (v) => setParam(ty, p.key, v), { path: key, placeholder: gameDef });
        const inp = ctl.querySelector('input');
        inp.addEventListener('input', () => { const v = parseFloat(inp.value); preview((cc) => { if (isFinite(v)) cc[ty][p.key] = v / 100; else delete cc[ty][p.key]; }); });
      } else {
        ctl = Forms.numberInput(def, own[p.key], (v) => setParam(ty, p.key, v), { path: key, inherit: { value: gameDef, from: 'the game\'s default' } });
        ctl.addEventListener('input', () => { const v = parseFloat(ctl.value); preview((cc) => { if (isFinite(v)) cc[ty][p.key] = v; else delete cc[ty][p.key]; }); });
      }
      const isOwn = own[p.key] != null;
      params.appendChild(Forms.row(Object.assign({}, def, { help: p.help, label: p.label }), ctl, { after: el('span', { class: 'muted small xpc-src', text: isOwn ? 'set here' : `the game's ${p.type === 'percent' ? fmtXp(gameDef * 100) + '%' : fmtXp(gameDef)}` }) }));
    }
    // XP needed × (its own row in fields.js; drawn here so the charts follow it)
    const multDef = FIELDS.SCALARS.find((d) => d.key === 'xp_need_mult');
    const multRow = Forms.fieldRow(multDef, tl);
    const multInp = multRow.querySelector('input');
    if (multInp) multInp.addEventListener('input', () => { const v = parseFloat(multInp.value); temp.mult = isFinite(v) ? Math.max(v, 0.01) : 1; redraw(); });
    params.appendChild(multRow);
    wrap.appendChild(params);

    // the checks (app.js lists the same in the inspector; errors block Save)
    const iss = M.issues(tl);
    if (iss.length) {
      const box = el('div', { class: 'xpc-issues' });
      for (const m of iss) box.appendChild(el('div', { class: 'xpc-issue ' + m.level }, el('b', { text: m.level === 'error' ? 'error' : 'warning' }), el('span', { text: m.msg })));
      wrap.appendChild(box);
    }

    // the charts, the table and the readout
    const chartsBox = el('div', { class: 'xpc-charts-box' });
    wrap.appendChild(chartsBox);
    redraw = () => { U.clear(chartsBox); chartsBox.appendChild(charts(curveNow(), multNow(), meta, !!temp.curve || temp.mult != null)); fillSim(curveNow(), multNow()); };

    // the latest sim's pace
    simBox = el('p', { class: 'small xpc-sim' });
    lastDraw = { curve: c, mult: mult0 };
    redraw();
    wrap.appendChild(simBox);
    fillSim(c, mult0);
    if (sim.state === 'idle') loadSim();

    // the other types' numbers, kept in the file but not played
    const kept = M.TYPES.filter((t) => t !== ty && U.isObj(c[t]) && Object.keys(c[t]).length);
    if (kept.length) {
      const names = kept.map((t) => (FIELDS.XP_TYPES.find((x) => x.v === t) || { label: t }).label);
      wrap.appendChild(el('p', { class: 'muted small xpc-kept' },
        `Kept in the file, not played: ${names.join(', ')}'s numbers (switch back to use them). `,
        el('button', { class: 'btn small ghost', type: 'button', text: 'Drop them', title: 'remove the numbers of the types not chosen from the file', onclick: () => App.apply((d) => { for (const t of kept) delete d.xp_curve[t]; tidy(d); }) })));
    }
    return wrap;
  }

  /** The table type's levels: unset shows the default table greyed with "Edit a copy"; set, a row per point
   *  (level, XP, ×), "+ level" and "Default table". */
  function pointsBlock(points, defPoints, preview) {
    const box = el('div', { class: 'xpc-points' });
    const has = Array.isArray(points);
    const list = has ? points : defPoints;
    const head = el('div', { class: 'xpc-pt-row head' }, el('span', { text: 'level' }), el('span', { text: 'XP it needs' }), el('span'));
    box.appendChild(head);
    list.forEach((p, k) => {
      const lv = el('input', { type: 'number', class: 'num short' + (has ? '' : ' inherited'), min: 1, step: 1, value: Array.isArray(p) ? p[0] : '', 'data-path': `xp_curve.table.points.${k}.0`, disabled: !has });
      const xp = el('input', { type: 'number', class: 'num' + (has ? '' : ' inherited'), min: 0, step: 'any', value: Array.isArray(p) ? p[1] : '', 'data-path': `xp_curve.table.points.${k}.1`, disabled: !has });
      if (has) {
        const commit = () => {
          const a = parseFloat(lv.value), b = parseFloat(xp.value);
          if (!isFinite(a) || !isFinite(b)) return;
          const pts = points.map((q) => q.slice());
          pts[k] = [Math.max(1, Math.round(a)), b];
          setPoints(pts);
        };
        const live = () => {
          const a = parseFloat(lv.value), b = parseFloat(xp.value);
          if (!isFinite(a) || !isFinite(b)) return;
          preview((cc) => { const pts = points.map((q) => q.slice()); pts[k] = [Math.max(1, Math.round(a)), b]; cc.table.points = pts; });
        };
        for (const i of [lv, xp]) {
          i.addEventListener('change', commit);
          i.addEventListener('input', live);
          i.addEventListener('keydown', (e) => { if (e.key === 'Enter') i.blur(); });
        }
      }
      const rm = el('button', { class: 'x', type: 'button', text: '×', title: has && points.length > 1 ? 'remove this level' : 'at least one level', disabled: !has || points.length <= 1, onclick: () => setPoints(points.filter((_, j) => j !== k)) });
      box.appendChild(el('div', { class: 'xpc-pt-row' }, lv, xp, rm));
    });
    const acts = el('div', { class: 'xpc-pt-acts' });
    if (!has) {
      acts.appendChild(el('span', { class: 'muted small', text: 'The game\'s default table (today\'s curve at these levels). ' }));
      acts.appendChild(el('button', { class: 'btn small', type: 'button', text: 'Edit a copy', title: 'start this map\'s own table from the default', onclick: () => setPoints(defPoints.map((q) => q.slice())) }));
    } else {
      acts.appendChild(el('button', { class: 'btn small', type: 'button', text: '+ level', title: 'a level 10 past the last, needing 30% more', onclick: () => {
        const last = points.length ? points[points.length - 1] : [0, 20];
        setPoints(points.concat([[Math.round(Number(last[0]) || 0) + 10, Math.round((Number(last[1]) || 20) * 1.3)]]));
      } }));
      acts.appendChild(el('button', { class: 'btn small ghost', type: 'button', text: 'Default table', title: 'drop this table: the game\'s default again', onclick: () => setPoints(null) }));
    }
    box.appendChild(acts);
    return box;
  }

  // ------------------------------------------------------------------ the charts

  /** The two charts (per level, in all), the legend, the readout under them and the table of stage levels. */
  function charts(curve, mult, meta, previewing) {
    const N = view.range;
    const mine = M.series(curve, mult, N);
    const base = M.series(TODAY, mult, N);
    const showBase = !same(mine, base);
    const box = el('div', { class: 'xpc-charts' + (previewing ? ' previewing' : '') });
    // the controls: the range and the scale, one row above the charts
    const ctl = el('div', { class: 'xpc-ctl' }, el('span', { class: 'muted small', text: 'Levels' }));
    for (const r of RANGES) ctl.appendChild(el('button', { class: 'btn small' + (r === N ? ' primary' : ''), type: 'button', text: `1–${r}`, onclick: () => { view.range = r; saveView(); App.render('tab'); } }));
    const logBtn = el('button', { class: 'btn small toggle' + (view.log ? ' on' : ''), type: 'button', text: 'Log scale', 'aria-pressed': view.log ? 'true' : 'false', title: 'each step up the axis = ten times more XP (an exponential curve becomes a straight line)', onclick: () => { view.log = !view.log; saveView(); App.render('tab'); } });
    ctl.appendChild(logBtn);
    if (previewing) ctl.appendChild(el('span', { class: 'xpc-preview small', text: 'preview: press Enter or leave the box to keep it' }));
    box.appendChild(ctl);
    const legend = el('div', { class: 'xpc-legend small' },
      el('span', { class: 'lg mine', text: `${meta.label} × ${fmtXp(mult)}` }),
      showBase ? el('span', { class: 'lg base', text: `today's curve (15 + 6L + L²/2) × ${fmtXp(mult)}` }) : el('span', { class: 'muted', text: '(today\'s curve: the same line)' }));
    box.appendChild(legend);
    const pair = el('div', { class: 'xpc-pair' });
    const hovers = [];
    const read = el('div', { class: 'xpc-read small' });
    const say = (L) => {
      const a = mine[L - 1], b = base[L - 1];
      const vs = (x, y) => (showBase ? ` <span class="muted">(today's ${fmtXp(y)}${y > 0 ? `, ×${(x / y).toFixed(2)}` : ''})</span>` : '');
      read.innerHTML = `<b>Level ${L}</b> → ${L + 1} needs <b>${fmtXp(a.need)}</b> XP${vs(a.need, b.need)} · reaching level ${L} takes <b>${fmtXp(a.cum)}</b> XP in all${vs(a.cum, b.cum)}`;
    };
    const hover = (L) => { for (const h of hovers) h(L); if (L) say(L); else say(Math.min(30, N)); };
    pair.appendChild(chart('per', 'XP each level needs', mine, base, showBase, N, hovers, hover));
    pair.appendChild(chart('cum', 'XP to reach the level, in all', mine, base, showBase, N, hovers, hover));
    box.appendChild(pair);
    box.appendChild(read);
    say(Math.min(30, N));
    box.appendChild(levelTable(mine, base, showBase, N));
    return box;
  }

  /** One chart: x = the level 1..N, y = the XP (linear from 0, or log), the chosen curve solid, today's dashed. */
  function chart(kind, title, mine, base, showBase, N, hovers, hover) {
    const W = 560, H = 250, L0 = 50, R = 14, T = 12, B = 30;
    const val = (p) => (kind === 'per' ? p.need : p.cum);
    const from = kind === 'cum' ? 2 : 1;   // reaching level 1 takes nothing
    const pts = (s) => s.filter((p) => p.L >= from);
    const all = pts(mine).concat(showBase ? pts(base) : []).map(val).filter((v) => isFinite(v));
    const maxV = Math.max(...all, 1), minV = Math.min(...all.filter((v) => v > 0), maxV);
    const x = (L) => L0 + (W - L0 - R) * (L - 1) / Math.max(N - 1, 1);
    let y, ticks;
    if (view.log) {
      const lt = logTicks(minV, maxV);
      ticks = lt.ticks;
      const a = Math.log10(lt.lo), b = Math.log10(lt.hi);
      y = (v) => T + (H - T - B) * (1 - (Math.log10(Math.max(v, lt.lo)) - a) / (b - a));
    } else {
      const lt = linTicks(maxV, 4);
      ticks = lt.ticks;
      y = (v) => T + (H - T - B) * (1 - v / lt.top);
    }
    const s = svg('svg', { class: 'xpc-svg', viewBox: `0 0 ${W} ${H}`, width: '100%', role: 'img', 'aria-label': `${title}, levels 1 to ${N}` });
    for (const v of ticks) {
      s.appendChild(svg('line', { x1: L0, y1: y(v), x2: W - R, y2: y(v), class: 'xpc-grid' }));
      s.appendChild(svg('text', { x: L0 - 6, y: y(v) + 3.5, class: 'xpc-tick end', text: fmtK(v) }));
    }
    const step = N <= 30 ? 5 : 10;
    for (let L = 1; L <= N; L += (L === 1 ? step - 1 : step)) {
      s.appendChild(svg('line', { x1: x(L), y1: H - B, x2: x(L), y2: H - B + 4, class: 'xpc-axis' }));
      s.appendChild(svg('text', { x: x(L), y: H - B + 15, class: 'xpc-tick mid', text: String(L) }));
    }
    s.appendChild(svg('line', { x1: L0, y1: H - B, x2: W - R, y2: H - B, class: 'xpc-axis' }));
    s.appendChild(svg('text', { x: W - R, y: H - 3, class: 'xpc-axis-t end', text: 'hero level' }));
    const path = (ser) => pts(ser).map((p, k) => `${k ? 'L' : 'M'}${x(p.L).toFixed(1)},${y(val(p)).toFixed(1)}`).join(' ');
    if (showBase) s.appendChild(svg('path', { d: path(base), class: 'xpc-base' }));
    s.appendChild(svg('path', { d: path(mine), class: 'xpc-mine' }));
    // the crosshair and the dots
    const cross = svg('line', { x1: 0, y1: T, x2: 0, y2: H - B, class: 'xpc-cross', visibility: 'hidden' });
    const dotB = svg('circle', { r: 3.5, class: 'xpc-dot base', visibility: 'hidden' });
    const dotM = svg('circle', { r: 4, class: 'xpc-dot mine', visibility: 'hidden' });
    s.appendChild(cross); s.appendChild(dotB); s.appendChild(dotM);
    hovers.push((L) => {
      const on = L && L >= from;
      for (const n of [cross, dotM]) n.setAttribute('visibility', on ? 'visible' : 'hidden');
      dotB.setAttribute('visibility', on && showBase ? 'visible' : 'hidden');
      if (!on) return;
      cross.setAttribute('x1', x(L)); cross.setAttribute('x2', x(L));
      dotM.setAttribute('cx', x(L)); dotM.setAttribute('cy', y(val(mine[L - 1])));
      dotB.setAttribute('cx', x(L)); dotB.setAttribute('cy', y(val(base[L - 1])));
    });
    const hit = svg('rect', { x: L0 - 6, y: 0, width: W - L0 - R + 12, height: H - B + 6, class: 'xpc-hit' });
    hit.addEventListener('mousemove', (ev) => {
      const r = s.getBoundingClientRect();
      const px = (ev.clientX - r.left) * W / r.width;
      const L = Math.max(1, Math.min(N, Math.round(1 + (px - L0) / (W - L0 - R) * (N - 1))));
      hover(L);
    });
    hit.addEventListener('mouseleave', () => hover(0));
    s.appendChild(hit);
    return el('figure', { class: 'xpc-fig' }, el('figcaption', { class: 'small', text: title }), s);
  }

  /** The numbers behind the charts at the levels a designer reads (a table: the charts' text view). */
  function levelTable(mine, base, showBase, N) {
    const levels = [5, 10, 20, 30, 40, 60, 80, 100].filter((L) => L <= N);
    const t = el('table', { class: 'xpc-table small' });
    const hr = el('tr', {}, el('th', { text: 'Level' }));
    for (const L of levels) hr.appendChild(el('th', { text: String(L) }));
    t.appendChild(el('thead', {}, hr));
    const tb = el('tbody');
    const row = (label, f, cls) => { const r = el('tr', { class: cls || '' }, el('th', { text: label })); for (const L of levels) r.appendChild(el('td', { text: fmtXp(f(L)) })); tb.appendChild(r); };
    row('needs (this curve)', (L) => mine[L - 1].need);
    if (showBase) row('needs (today\'s)', (L) => base[L - 1].need, 'dim');
    row('in all to reach it', (L) => mine[L - 1].cum);
    if (showBase) row('in all (today\'s)', (L) => base[L - 1].cum, 'dim');
    t.appendChild(tb);
    return el('div', { class: 'xpc-table-wrap' }, t);
  }

  // ------------------------------------------------------------------ the latest sim's pace

  async function loadSim() {
    sim.state = 'loading';
    try {
      // the result the Sim tab shows, else the newest finished sim of this map
      let id = '', label = '';
      const cur = typeof Sim !== 'undefined' && Sim.S && Sim.S.current;
      if (cur && cur.meta && cur.meta.id && cur.series && cur.series.xp_total) {
        sim.id = cur.meta.id;
        sim.xp = cur.series.xp_total.mean || null;
        sim.label = simWords(cur.settings || {}, cur.meta.started);
        sim.T = (cur.t || []).length;
        sim.state = sim.xp ? 'done' : 'none';
        fillSim(lastDraw && lastDraw.curve, lastDraw && lastDraw.mult);
        return;
      }
      const r = await fetch('/api/sim/history', { cache: 'no-store' });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      const h = await r.json();
      const mapId = App.S.mapId;
      const ok = (h.sims || []).filter((x) => x.has_result && !x.synthetic && x.state === 'done' && (!x.settings || !x.settings.map || x.settings.map === mapId));
      ok.sort((a, b) => (b.started_epoch || 0) - (a.started_epoch || 0));
      if (!ok.length) { sim.state = 'none'; fillSim(lastDraw && lastDraw.curve, lastDraw && lastDraw.mult); return; }
      id = ok[0].id;
      label = simWords(ok[0].settings || {}, ok[0].started, ok[0].hero_name);
      const rr = await fetch(`/api/sim/result/${encodeURIComponent(id)}`, { cache: 'no-store' });
      if (!rr.ok) throw new Error(`HTTP ${rr.status}`);
      const res = await rr.json();
      const xp = res && res.series && res.series.xp_total ? res.series.xp_total.mean : null;
      Object.assign(sim, { id, label, xp, T: (res.t || []).length, state: xp ? 'done' : 'none' });
    } catch (e) {
      sim.state = 'error';
      sim.err = e.message;
    }
    fillSim(lastDraw && lastDraw.curve, lastDraw && lastDraw.mult);
  }

  function simWords(st, started, heroName) {
    const when = started ? new Date(started) : null;
    const hm = when && !isNaN(when.getTime()) ? `${when.getMonth() + 1}/${when.getDate()} ${String(when.getHours()).padStart(2, '0')}:${String(when.getMinutes()).padStart(2, '0')}` : '';
    return `${hm} · ${heroName || st.hero || 'a hero'} ×${st.players || '?'} to ${fmtT(Number(st.limit) || 0)}`;
  }

  /** The line under the charts: when a run gaining XP as the latest sim did reaches levels 10, 20 and 30 with this curve
   *  (and with today's), or why there is no such line. */
  function fillSim(curve, mult) {
    if (!simBox) return;
    U.clear(simBox);
    const again = el('button', { class: 'btn small ghost', type: 'button', text: 'Refresh', title: 'read the newest sim again', onclick: () => { sim.state = 'idle'; loadSim(); } });
    if (sim.state === 'loading' || sim.state === 'idle') { simBox.appendChild(el('span', { class: 'muted', text: 'Reading the latest sim…' })); return; }
    if (sim.state === 'error') { simBox.append(el('span', { class: 'muted', text: `The latest sim could not be read (${sim.err}). ` }), again); return; }
    if (sim.state === 'none' || !Array.isArray(sim.xp)) { simBox.append(el('span', { class: 'muted', text: 'No sim of this map yet: run one in the Sim tab to see when a run reaches levels 10, 20 and 30 with this curve. ' }), again); return; }
    const c = curve || {}, m = mult || 1;
    const at = (cv, L) => { const s = M.secondsToLevel(cv, m, sim.xp, L); return s == null ? `not by ${fmtT(Math.max(sim.T - 1, 0))}` : `at ${fmtT(s)}`; };
    const levels = [10, 20, 30];
    const mineW = levels.map((L) => `level ${L} <b>${at(c, L)}</b>`).join(', ');
    const baseW = levels.map((L) => at(TODAY, L)).join(', ');
    const sameCurve = levels.every((L) => at(c, L) === at(TODAY, L)) && M.typeOf(c) === 'quadratic';
    const span = el('span');
    span.innerHTML = `At the XP a second of the latest sim (${esc(sim.label)}): ${mineW}${sameCurve ? '' : ` <span class="muted">(today's curve: ${baseW})</span>`}. <span class="muted">A rough guide: the sim's kills came with its own levels and cards, so a slower or faster curve changes them too; run the sim again for the real thing.</span> `;
    simBox.append(span, again);
  }

  return { block, fmtXp, fmtK, linTicks, logTicks };
})();
