// The Timeline tab (pass 53, pass 54): the calendar. A ruler with the stages, then one lane per part of the timeline (cap,
// HP x, ATK x, roster, share, waves, events, specials, paths), all on one time axis (x = seconds / spp), scrolling
// together, zoomable, with a cursor that follows the mouse and a readout of what the director would be doing at that
// second. Everything is drawn again from App.S on every change (a few thousand SVG nodes: cheap), so the drawing code
// never has to patch anything. Pass 54: a roster row's bar is a little graph of its presence keyframes (drag the points,
// double-click to add or remove one), the rows reorder from a gutter at the left, the Share band stacks each creature's
// share of the draw, and hovering a bar, a block, a stripe, a flag or the specials band shows a card with the creature's
// HP and ATK at that second. Pass 57: the "Spawned so far" lane under the cap (model.js spawnEstimate: every creature a run
// spawns by each second, with its hover card and the kill rate / boss fight / portal wait boxes in its label).
'use strict';

const Timeline = (() => {
  const { el, svg, fmtT, fmtN, clear, glyph } = U;
  const LABEL_W = 170;
  const RULER_H = 60, CAP_H = 124, CURVE_H = 84, ROW_H = 36, ROSTER_HEAD = 40, EV_H = 92, SP_H = 42, PATH_H = 32, PAD = 6;
  const ALT_COLORS = ['#3987e5', '#d95926', '#199e70', '#c98500', '#d55181', '#9085e9', '#e66767', '#4cb5c3'];
  const HANDLE = 8;
  const CAP_HELP = 'The points are the control points of the live cap curve (how many creatures may be alive): linear between them, flat before the first and after the last. They are not spawn events: the director spawns up to the cap on its own interval.';
  // pass 57: the "Spawned so far" lane under the cap
  const SPAWN_H = 132;
  const SPAWN_HELP = 'Every creature a run has spawned by each second, counted from 0:00: the regular crowd (blue), the coloured specials among it (orange), the elite-modified (purple) and the Elites, specials and bosses (gold, marked where they arrive). An estimate: a run only spawns what the hero kills, so it assumes the hero kills a share of the living crowd each second (from your own runs; the boxes change it) while the director refills to the cap under every rule of the timeline. Hover for the numbers.';
  let spp = 1.0;                       // seconds per pixel
  let root = null, scrollBox = null, content = null, cursorEl = null, readout = null, card = null, menu = null;
  const lanes = {};                    // name -> {row, label, svg}
  let drag = null;
  let raf = 0;
  let frozenMax = null;                // the roster's weight scale, held while a presence point is dragged
  let hovers = {};                     // data-hover key -> (t) => card content (rebuilt every render)

  // ------------------------------------------------------------------ DOM

  function mount(container) {
    root = container;
    clear(root);
    scrollBox = el('div', { class: 'tl-scroll' });
    content = el('div', { class: 'tl-content' });
    scrollBox.appendChild(content);
    const spec = [
      ['ruler', 'Time', null, 'ruler', ''],
      ['cap', 'Cap', null, '', CAP_HELP],
      ['spawned', 'Spawned so far', null, '', SPAWN_HELP],
      ['hp', 'HP ×', null, '', 'Creature health over the run clock (hp_curve): click to edit the curve, drag its points, double-click to add or remove one.'],
      ['dmg', 'ATK ×', null, '', 'Creature damage over the run clock (damage_curve): click to edit, drag its points, double-click to add or remove one.'],
      ['roster', 'Roster', { text: '+ Row', title: 'Add a roster row at the view\'s centre', onclick: () => App.newRow(null, viewCenter()) }, '', ''],
      ['share', 'Share', null, '', 'Each creature\'s share of the draw over time, stacked, normalised per channel; click for the table.'],
      ['waves', 'Waves', { text: '+ Wave', title: 'Add a wave at the view\'s centre', onclick: () => App.newWave(null, viewCenter()) }, '', ''],
      ['events', 'Events', { text: '+ Event', title: 'Add an event at the view\'s centre', onclick: (e) => eventMenu(e.currentTarget) }, '', ''],
      ['specials', 'Specials', null, '', ''],
      ['paths', 'Paths', null, '', ''],
    ];
    for (const [name, title, plus, cls, help] of spec) {
      const head = name === 'roster' ? el('div', { class: 'lane-head' }, el('div', {}, el('div', { class: 'lane-name', text: title }), el('div', { class: 'lane-sub' }))) : null;
      const label = head
        ? el('div', { class: 'lane-label roster-label' }, head, el('div', { class: 'gutter' }))
        : el('div', { class: 'lane-label', title: help }, el('div', { class: 'lane-name', text: title }), el('div', { class: 'lane-sub' }), name === 'share' ? el('div', { class: 'share-legend' }) : null);
      if (plus) (head || label).appendChild(el('button', { class: 'btn small plus', text: plus.text, title: plus.title, onclick: plus.onclick }));
      if (name === 'spawned') label.appendChild(spawnControls());
      const s = svg('svg', { class: 'lane-svg', height: 10 });
      const row = el('div', { class: 'lane lane-' + name + (cls ? ' ' + cls : '') }, label, s);
      label.addEventListener('click', (e) => {
        if (e.target.tagName === 'BUTTON' || e.target.closest('.gutter')) return;
        if (['cap', 'hp', 'dmg', 'share', 'specials', 'paths'].includes(name)) App.select({ kind: name });
      });
      content.appendChild(row);
      lanes[name] = { row, label, svg: s };
    }
    cursorEl = el('div', { class: 'tl-cursor', hidden: true });
    content.appendChild(cursorEl);
    readout = el('div', { class: 'readout', hidden: true });
    document.body.appendChild(readout);
    card = el('div', { class: 'hovercard', hidden: true });
    document.body.appendChild(card);
    root.appendChild(scrollBox);
    scrollBox.addEventListener('pointermove', onHover);
    scrollBox.addEventListener('pointerleave', () => { if (!drag) hideCursor(); });
    scrollBox.addEventListener('wheel', onWheel, { passive: false });
    scrollBox.addEventListener('pointerdown', (e) => { if (e.target === content || e.target === scrollBox || e.target.classList.contains('lane-svg')) { if (e.button === 0) App.select(null); } });
    window.addEventListener('resize', () => { if (App.S.map && App.S.tab === 'timeline') render(); });
  }

  // A double-click is detected by hand (same key, under 450 ms, within 8 px): the first click re-renders the lane, so the
  // element under the pointer is a new one by the second click and the browser's own dblclick never completes on it.
  let lastTap = { key: '', t: 0, x: 0, y: 0 };
  // a pattern's label as the field's picker shows it ("In front", not "in_front"; pass 57)
  function patternLabel(v) {
    const o = FIELDS.PATTERNS.find((p) => p.v === v) || FIELDS.SWARM_PATTERNS.find((p) => p.v === v);
    return o ? o.label : v;
  }

  function isDoubleTap(key, e) {
    const now = performance.now();
    const dbl = lastTap.key === key && now - lastTap.t < 450 && Math.abs(e.clientX - lastTap.x) < 8 && Math.abs(e.clientY - lastTap.y) < 8;
    lastTap = dbl ? { key: '', t: 0, x: 0, y: 0 } : { key, t: now, x: e.clientX, y: e.clientY };
    return dbl;
  }

  const svgLeft = () => lanes.ruler.svg.getBoundingClientRect().left;
  const x = (t) => t / spp;
  const tAt = (clientX) => (clientX - svgLeft()) * spp;
  const contentWidth = () => Math.ceil(App.viewEnd() / spp) + 60;

  function viewCenter() {
    if (!scrollBox) return 0;
    const visible = scrollBox.clientWidth - LABEL_W;
    return Math.max(0, Math.min(App.runEnd(), (scrollBox.scrollLeft + visible / 2) * spp));
  }

  function fit() {
    if (!scrollBox) return;
    const w = Math.max(200, scrollBox.clientWidth - LABEL_W - 40);
    spp = App.viewEnd() / w;
    scrollBox.scrollLeft = 0;
    render();
  }

  /** Zoom by `factor` (under 1 = closer) keeping the time under `clientX` (or the view centre) where it is. */
  function zoom(factor, clientX) {
    if (!scrollBox) return;
    const anchorX = clientX == null ? scrollBox.getBoundingClientRect().left + LABEL_W + (scrollBox.clientWidth - LABEL_W) / 2 : clientX;
    const t = tAt(anchorX);
    const before = spp;
    spp = Math.min(20, Math.max(0.02, spp * factor));
    if (spp === before) return;
    render();
    const px = anchorX - scrollBox.getBoundingClientRect().left - LABEL_W;
    scrollBox.scrollLeft = Math.max(0, x(t) - px);
    updateZoomLabel();
  }

  function updateZoomLabel() {
    const z = document.getElementById('zoom-label');
    if (z) z.textContent = spp >= 1 ? `1 px = ${fmtN(spp, 2)} s` : `${fmtN(1 / spp, 1)} px = 1 s`;
  }

  function onWheel(e) {
    if (e.ctrlKey) { e.preventDefault(); zoom(e.deltaY > 0 ? 1.25 : 0.8, e.clientX); }
  }

  function scrollToSelection() {
    const sel = App.S.sel;
    if (!sel || sel.i == null) return;
    const it = App.selected();
    if (!it) return;
    const px = x(Number(it.t) || 0);
    const visible = scrollBox.clientWidth - LABEL_W;
    if (px < scrollBox.scrollLeft + 20 || px > scrollBox.scrollLeft + visible - 20) scrollBox.scrollLeft = Math.max(0, px - visible / 3);
    if (sel.kind === 'roster') {
      // a row low on a long roster: bring it into view vertically too
      const top = lanes.roster.row.offsetTop + ROSTER_HEAD + sel.i * ROW_H;
      if (top < scrollBox.scrollTop + RULER_H || top + ROW_H > scrollBox.scrollTop + scrollBox.clientHeight) scrollBox.scrollTop = Math.max(0, top - scrollBox.clientHeight / 3);
    }
  }

  // ------------------------------------------------------------------ the "+ Event" menu

  function eventMenu(anchor) {
    closeMenu();
    menu = el('div', { class: 'menu' });
    for (const [type, info] of Object.entries(FIELDS.EVENT_TYPES)) {
      menu.appendChild(el('button', { class: 'menu-item', onclick: () => { closeMenu(); App.newEvent(type, viewCenter()); } }, glyph(info.glyph), el('span', { text: info.label }), el('small', { text: info.help })));
    }
    document.body.appendChild(menu);
    // under the button, or above it when the window's bottom is too close (the Events lane sits low on the page)
    const r = anchor.getBoundingClientRect();
    const mh = menu.offsetHeight, mw = menu.offsetWidth;
    menu.style.left = `${Math.max(4, Math.min(r.left, window.innerWidth - mw - 8))}px`;
    menu.style.top = `${r.bottom + 4 + mh <= window.innerHeight - 8 ? r.bottom + 4 : Math.max(4, r.top - 4 - mh)}px`;
    setTimeout(() => document.addEventListener('pointerdown', onDocDown, { once: true }), 0);
  }
  function onDocDown(e) { if (menu && !menu.contains(e.target)) closeMenu(); else if (menu) setTimeout(() => document.addEventListener('pointerdown', onDocDown, { once: true }), 0); }
  function closeMenu() { if (menu) { menu.remove(); menu = null; } }

  // ------------------------------------------------------------------ render

  function render() {
    if (!root || !App.S.map) return;
    hovers = {};
    if (!drag) hideCard();
    const w = contentWidth();
    content.style.width = `${LABEL_W + w}px`;
    for (const name of Object.keys(lanes)) lanes[name].svg.setAttribute('width', w);
    renderRuler(w);
    renderCap(w);
    renderSpawned(w);
    renderCurve(w, 'hp', 'hp_curve');
    renderCurve(w, 'dmg', 'damage_curve');
    renderRoster(w);
    renderShare(w);
    renderWaves(w);
    renderEvents(w);
    renderSpecials(w);
    renderPaths(w);
    const selKey = App.selKey();
    for (const name of ['cap', 'hp', 'dmg', 'share', 'specials', 'paths']) lanes[name].row.classList.toggle('selected', selKey === name);
    updateZoomLabel();
  }

  function setHeight(name, h) {
    lanes[name].svg.setAttribute('height', h);
    lanes[name].row.style.height = `${h}px`;
  }

  function issueBadge(key, px, py) {
    const m = App.issuesFor(key);
    if (!m) return null;
    return svg('g', { class: 'issue ' + m.level }, svg('title', {}, m.msgs.join('\n')),
      svg('circle', { cx: px, cy: py, r: 7 }), svg('text', { x: px, y: py + 3.6, 'text-anchor': 'middle', class: 'issue-mark', text: '!' }));
  }

  const issueClass = (key) => { const m = App.issuesFor(key); return m ? ' has-' + m.level : ''; };

  // ------------------------------------------------------------------ ruler

  function tickStep() {
    for (const s of [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1200]) if (s / spp >= 72) return s;
    return 1800;
  }

  function renderRuler(w) {
    const s = clear(lanes.ruler.svg);
    setHeight('ruler', RULER_H);
    const SL = App.stageLength(), n = App.stages(), end = App.viewEnd();
    const names = ['stage-1', 'stage-2', 'stage-3', 'stage-4'];
    for (let k = 0; k < n; k++) {
      const a = k * SL, b = Math.min((k + 1) * SL, end);
      s.appendChild(svg('rect', { x: x(a), y: 0, width: Math.max(0, x(b) - x(a)), height: 20, class: 'band ' + names[Math.min(k, 3)] }));
      s.appendChild(svg('text', { x: x(a) + 6, y: 14, class: 'band-text', text: `Stage ${k + 1}  ${fmtT(a)} – ${fmtT((k + 1) * SL)}  ×${fmtN(App.stageMult(k), 2)}` }));
    }
    s.appendChild(svg('rect', { x: x(App.runEnd()), y: 0, width: Math.max(0, x(end) - x(App.runEnd())) + 60, height: 20, class: 'band endless' }));
    s.appendChild(svg('text', { x: x(App.runEnd()) + 6, y: 14, class: 'band-text', text: `Endless  (every ${App.tl().endless_wave_seconds || 60} s ×${App.tl().endless_wave_mult || 1})` }));
    const step = tickStep();
    for (let t = 0; t <= end; t += step / 2) {
      const major = Math.abs((t / step) - Math.round(t / step)) < 1e-6;
      s.appendChild(svg('line', { x1: x(t), x2: x(t), y1: major ? 24 : 32, y2: 40, class: major ? 'tick' : 'tick minor' }));
      if (major) s.appendChild(svg('text', { x: x(t) + 3, y: 54, class: 'tick-text', text: fmtT(t) }));
    }
    // skulls for the bosses, crowns for the Elites, on the ruler too (they are the landmarks of a run)
    (App.tl().events || []).forEach((ev, i) => {
      if (ev.type !== 'boss' && ev.type !== 'elite_boss') return;
      const info = FIELDS.EVENT_TYPES[ev.type];
      const g = svg('g', { class: 'flag', transform: `translate(${x(Number(ev.t) || 0) - 8}, 22)`, 'data-hover': `event:${i}`, onclick: () => App.select({ kind: 'event', i }) },
        svg('rect', { x: -2, y: -1, width: 20, height: 20, rx: 4, class: 'flag-bg' }),
        svg('use', { href: '#g-' + info.glyph, width: 16, height: 16, fill: info.color }));
      hovers[`event:${i}`] = () => eventCard(i);
      s.appendChild(g);
    });
    lanes.ruler.label.querySelector('.lane-sub').textContent = `${n} stages × ${fmtT(SL)}`;
  }

  // ------------------------------------------------------------------ cap

  function renderCap(w) {
    const s = clear(lanes.cap.svg);
    setHeight('cap', CAP_H);
    const d = App.tl();
    const end = App.viewEnd();
    const hard = Number(d.hard_cap) || 0;
    let maxV = Math.max(hard, Number(d.cap_max) || 0, 10);
    for (const p of d.cap_curve || []) maxV = Math.max(maxV, Number(p[1]) || 0);
    maxV *= 1.08;
    const top = 10, bottom = CAP_H - 14;
    const y = (v) => bottom - (v / maxV) * (bottom - top);
    // grid: a few round values
    const gstep = maxV > 200 ? 100 : maxV > 80 ? 50 : maxV > 30 ? 20 : 10;
    for (let v = gstep; v < maxV; v += gstep) {
      s.appendChild(svg('line', { x1: 0, x2: w, y1: y(v), y2: y(v), class: 'grid' }));
      s.appendChild(svg('text', { x: 4, y: y(v) - 2, class: 'grid-text', text: v }));
    }
    if (hard > 0) {
      s.appendChild(svg('line', { x1: 0, x2: w, y1: y(hard), y2: y(hard), class: 'hard-cap' }));
      s.appendChild(svg('text', { x: 4, y: y(hard) - 3, class: 'hard-cap-text', text: `hard cap ${hard} bodies` }));
    }
    // the hell channel's cap (a share of the regular one per stage)
    if ((d.hell_cap || []).some((h) => Number(h) > 0)) {
      let pts = '';
      for (let px = 0; px <= x(end); px += 4) pts += `${px},${y(App.hellCapAt(px * spp))} `;
      s.appendChild(svg('polyline', { points: pts, class: 'hell-cap' }, svg('title', {}, 'the hell channel\'s cap (hell_cap × the regular cap)')));
    }
    // the effective cap, sampled (cap_max and cap_per_stage apply on top of the curve)
    let pts = '';
    for (let px = 0; px <= x(end); px += 3) pts += `${px},${y(App.capAt(px * spp))} `;
    pts += `${x(end)},${y(App.capAt(end))}`;
    s.appendChild(svg('polyline', { points: pts, class: 'cap-line' + issueClass('cap') }));
    // boss fights keep boss_cap_frac of the cap: a dip at each boss event (the clock stands still, so it has no width)
    const frac = d.boss_cap_frac == null ? 0.3 : Number(d.boss_cap_frac);
    for (const ev of d.events || []) {
      if (ev.type !== 'boss') continue;
      const t = Number(ev.t) || 0, cap = App.capAt(t);
      // pass 57: the fight reads the cap a hair past its second (the frame that fired the event is past it), so on a
      // step of the curve it keeps its share of the step's far side: Red Canyon's first fight is 0.6 of 54, not of 100
      // (the run records show 32). The stage's cap_per_stage stays the fight's own stage's.
      const capIn = Math.max(0, App.capAt(t + 1e-4) - (Number(d.cap_per_stage) || 0) * (App.stageAt(t + 1e-4) - App.stageAt(Math.max(0, t - 1e-4))));
      const px = x(t);
      const dip = svg('path', { d: `M${px - 9},${y(cap)} L${px - 4},${y(capIn * frac)} L${px + 4},${y(capIn * frac)} L${px + 9},${y(cap)} Z`, class: 'boss-dip' });
      if (capIn !== cap) dip.appendChild(svg('title', {}, `the fight reads the cap just past ${fmtT(t)}: the curve steps from ${cap} to ${capIn} there, so the fight keeps ${fmtN(frac, 2)} × ${capIn} = ${Math.floor(capIn * frac)}`));
      s.appendChild(dip);
      s.appendChild(svg('text', { x: px + 11, y: y(capIn * frac) + 4, class: 'dip-text', text: `boss ×${fmtN(frac, 2)} = ${Math.floor(capIn * frac)}${capIn !== cap ? ` (of ${capIn})` : ''}` }));
    }
    // a wide invisible stroke takes the clicks: one selects the lane, a double one adds a point where it landed
    const hit = svg('polyline', { points: pts, class: 'cap-hit' }, svg('title', {}, `${CAP_HELP}\nClick to edit; double-click to add a point here.`));
    hit.addEventListener('pointerdown', (e) => {
      if (e.button !== 0) return;
      e.stopPropagation();
      if (!isDoubleTap('cap-line', e)) { App.select({ kind: 'cap' }); return; }
      e.preventDefault();
      const t = Math.max(0, Math.round(tAt(e.clientX)));
      const r = lanes.cap.svg.getBoundingClientRect();
      const v = Math.max(0, Math.round(((bottom - (e.clientY - r.top)) / (bottom - top)) * maxV));
      App.apply((tl) => {
        if (!Array.isArray(tl.cap_curve)) tl.cap_curve = [];
        tl.cap_curve.push([t, v]);
        tl.cap_curve.sort((a, b) => a[0] - b[0]);
        App.S.sel = { kind: 'cap' };
      });
      App.toast(`Added a cap point: ${fmtT(t)} → ${v}`);
    });
    s.appendChild(hit);
    (d.cap_curve || []).forEach((p, k) => {
      // pass 54: every point carries its cap as a faint label (the time and the value in full on hover)
      const c = svg('g', { class: 'cap-point', transform: `translate(${x(Number(p[0]) || 0)}, ${y(Number(p[1]) || 0)})` },
        svg('title', {}, `${fmtT(p[0])} → cap ${p[1]}: a control point of the cap curve, not a spawn event (drag; double-click to remove)`),
        svg('circle', { r: 6 }), svg('text', { x: 8, y: -7, class: 'pt-text', text: String(p[1]) }), svg('text', { x: 8, y: 13, class: 'pt-time', text: fmtT(p[0]) }));
      c.addEventListener('pointerdown', (e) => {
        if (e.button !== 0) return;
        if (!isDoubleTap(`cap-point:${p[0]}:${p[1]}`, e)) { startDrag(e, { kind: 'cap', k, y, maxV, top, bottom }); return; }
        e.stopPropagation(); e.preventDefault();
        App.apply((tl) => { tl.cap_curve.splice(k, 1); App.S.sel = { kind: 'cap' }; });
        App.toast('Removed a cap point', { undo: true });
      });
      s.appendChild(c);
    });
    if (!(d.cap_curve || []).length) s.appendChild(svg('text', { x: 8, y: top + 12, class: 'hint-text', text: `straight line: cap_start ${d.cap_start} + ${d.cap_per_minute} a minute (double-click the line to start a curve)` }));
    const b = issueBadge('cap', 14, 14);
    if (b) s.appendChild(b);
    lanes.cap.label.querySelector('.lane-sub').textContent = `${plural((d.cap_curve || []).length, 'control point')} · hard ${hard}`;
  }

  // ------------------------------------------------------------------ spawned so far (pass 57)

  // Garry: "I want to be able to hover over this data and get actual numbers of totals ever spawned."
  const GEAR = 'M8 5.3a2.7 2.7 0 1 0 0 5.4 2.7 2.7 0 1 0 0-5.4zM6.9 1h2.2l.3 1.8 1.2.5 1.5-1.1 1.6 1.6-1.1 1.5.5 1.2 1.8.3v2.2l-1.8.3-.5 1.2 1.1 1.5-1.6 1.6-1.5-1.1-1.2.5-.3 1.8H6.9l-.3-1.8-1.2-.5-1.5 1.1-1.6-1.6 1.1-1.5-.5-1.2L1 9.1V6.9l1.8-.3.5-1.2-1.1-1.5 1.6-1.6 1.5 1.1 1.2-.5z';
  const MARKS = { elite: { glyph: 'crown', color: '#e6a04a', what: 'an Elite' }, mod: { glyph: 'star', color: '#9085e9', what: 'elite-modified creatures' }, special: { glyph: 'gear', color: '#4cb5c3', what: 'a special' }, boss: { glyph: 'skull', color: '#e66767', what: 'a boss' } };
  const spawnInputs = {};
  let lastSpawn = null;              // the estimate the lane drew last (its hover card and the readout read it)

  /** A count as the cards print it: whole and grouped from 10 up, one decimal under 10 (an expected 0.3 of an Elite). */
  function fmtCount(n) {
    const v = Number(n) || 0;
    if (Math.abs(v) >= 10) return Math.round(v).toLocaleString('en-US');
    const r = Math.round(v * 10) / 10;
    return String(r);
  }

  /** The kill rate, boss fight and portal wait boxes in the lane's label: empty shows the fitted number as its
   *  placeholder (from Garry's runs), a typed one replaces it (↺ goes back). */
  function spawnControls() {
    const box = el('div', { class: 'sp-ctl' });
    const mk = (key, text, unit, step, toValue) => {
      const inp = el('input', { type: 'number', class: 'num sp-in', min: 0, step });
      inp.addEventListener('change', () => {
        const raw = inp.value.trim();
        const v = raw === '' ? null : Number(raw);
        App.setAssume(key, v == null || !isFinite(v) || v < 0 ? null : toValue(v));
      });
      inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') inp.blur(); });
      const reset = el('button', { class: 'sp-reset', type: 'button', text: '↺', title: 'back to the number from your runs', hidden: true, onclick: (e) => { e.stopPropagation(); App.setAssume(key, null); } });
      const row = el('label', { class: 'sp-row' }, el('span', { class: 'sp-lab', text }), inp, el('span', { class: 'sp-unit', text: unit }), reset);
      spawnInputs[key] = { inp, reset, row };
      return row;
    };
    box.appendChild(mk('turnover', 'kills', '%/s', 0.1, (v) => v / 100));
    box.appendChild(mk('bossSeconds', 'boss', 's', 1, (v) => v));
    box.appendChild(mk('portalSeconds', 'portal', 's', 1, (v) => v));
    return box;
  }

  /** The boxes show the page's own numbers, or the fitted ones as placeholders; each one's tooltip says where the
   *  number comes from. */
  function syncSpawnControls() {
    const f = App.S.fit;
    const a = App.S.assume;
    const fromRuns = f && f.source === 'records';
    const fitTv = fromRuns ? (Array.isArray(f.by_stage) && f.by_stage.length ? f.by_stage[0] : f.turnover) : Model.EST_DEF.turnover;
    const fitBoss = f && f.boss_seconds != null ? f.boss_seconds : Model.EST_DEF.bossSeconds;
    const fitPortal = f && f.portal_seconds != null ? f.portal_seconds : Model.EST_DEF.portalSeconds;
    const runs = fromRuns ? (f.runs || []).length : 0;
    const stagesTxt = fromRuns && Array.isArray(f.by_stage) && f.by_stage.length > 1 ? ` (${f.by_stage.map((v, k) => `stage ${k + 1} ${fmtN(v * 100, 1)} %`).join(', ')})` : '';
    const curveTxt = fromRuns && Array.isArray(f.curve) && f.curve.length ? ', minute by minute as your runs went (a young build kills slowly)' : '';
    const fits = {
      turnover: [fitTv * 100, `The share of the living crowd the hero kills a second. Empty = from ${fromRuns ? `your ${runs} run${runs === 1 ? '' : 's'} on this map: ${fmtN(fitTv * 100, 1)} %${stagesTxt}${curveTxt}` : 'the default 6 % (no runs on this map yet)'}. A number here replaces it for the whole run. 6 % = an average creature lives about 17 s.`, 1],
      bossSeconds: [fitBoss, `How long a boss fight lasts (the run clock stands still; the crowd keeps boss_cap_frac of the cap). Empty = ${f && f.fights ? `the mean of your ${f.fights} fight${f.fights === 1 ? '' : 's'}` : 'the default'}: ${fmtN(fitBoss, 1)} s.`, 0],
      portalSeconds: [fitPortal, `How long you stand at the portal before walking through (a portal wave, or portal_cap for portal_spawn_seconds; no specials). Empty = ${f && f.waits ? `the mean of your ${f.waits} wait${f.waits === 1 ? '' : 's'}` : 'the default'}: ${fmtN(fitPortal, 1)} s.`, 0],
    };
    for (const [key, [val, title, digits]] of Object.entries(fits)) {
      const c = spawnInputs[key];
      if (!c) continue;
      c.inp.placeholder = fmtN(val, digits);
      c.row.title = title;
      const own = a[key];
      const want = own == null ? '' : String(key === 'turnover' ? Model.round(own * 100, 2) : Model.round(own, 1));
      if (document.activeElement !== c.inp && c.inp.value !== want) c.inp.value = want;
      c.inp.classList.toggle('set', own != null);
      c.reset.hidden = own == null;
    }
  }

  /** Round grid steps for a count axis. */
  function countStep(span) {
    for (const s of [10, 20, 50, 100, 200, 250, 500, 1000, 2000, 2500, 5000, 10000, 20000, 50000]) if (span / s <= 4) return s;
    return 100000;
  }

  /** The lane: the run's cumulative spawns on the run clock, stacked (the plain crowd, its coloured specials, the
   *  elite-modified, the Elites + specials + bosses), the total as a line, a glyph where each Elite, elite modifier,
   *  special and boss arrives, a step at each boss fight (the clock stands still through it) and the second colour
   *  comes in. Hover anywhere for the numbers. */
  function renderSpawned(w) {
    const s = clear(lanes.spawned.svg);
    setHeight('spawned', SPAWN_H);
    stageShade(s, SPAWN_H);
    syncSpawnControls();
    const res = App.spawned(!!drag);
    lastSpawn = res;
    const est = res.est;
    const pts = est.points;
    let maxV = 10;
    for (const p of pts) if (p.all > maxV) maxV = p.all;
    maxV *= 1.12;
    const top = 14, bottom = SPAWN_H - 10;
    const y = (v) => bottom - (Math.max(0, v) / maxV) * (bottom - top);
    const g = svg('g', { class: 'spawned', 'data-hover': 'spawned' });
    g.appendChild(svg('rect', { x: 0, y: 0, width: w, height: SPAWN_H, class: 'sp-hit' }));
    const gstep = countStep(maxV);
    for (let v = gstep; v < maxV; v += gstep) {
      g.appendChild(svg('line', { x1: 0, x2: w, y1: y(v), y2: y(v), class: 'grid' }));
      g.appendChild(svg('text', { x: 4, y: y(v) - 2, class: 'grid-text', text: fmtCount(v) }));
    }
    // the stacked layers, bottom up: plain, coloured, elite-modified, then the Elites, specials and bosses
    const xs = pts.map((p) => x(p.t));
    const bounds = [
      pts.map(() => 0),
      pts.map((p) => Math.max(p.reg - p.col - p.mod, 0)),
      pts.map((p) => Math.max(p.reg - p.mod, 0)),
      pts.map((p) => p.reg),
      pts.map((p) => p.all),
    ];
    const layer = ['plain', 'col', 'mod', 'top'];
    for (let L = 0; L < 4; L++) {
      const upper = xs.map((px, i) => `${px},${y(bounds[L + 1][i])}`);
      const lower = xs.map((px, i) => `${px},${y(bounds[L][i])}`).reverse();
      g.appendChild(svg('polygon', { points: upper.concat(lower).join(' '), class: 'sp-area sp-' + layer[L] }));
    }
    g.appendChild(svg('polyline', { points: xs.map((px, i) => `${px},${y(bounds[4][i])}`).join(' '), class: 'sp-line' + (res.stale ? ' stale' : '') }));
    // colour comes in after colour_after_kills kills
    if (est.colourAt != null && est.colourAt > 0) {
      const cx = x(est.colourAt);
      g.appendChild(svg('line', { x1: cx, x2: cx, y1: top, y2: bottom, class: 'sp-colour' }));
      g.appendChild(svg('text', { x: cx + 3, y: bottom - 12, class: 'sp-colour-text', text: 'colour' }, svg('title', {}, `colour comes in at ${fmtT(est.colourAt)}: the run's ${App.tl().colour_after_kills || 0}th kill (colour_after_kills); from here the coloured specials and the elite modifiers come`)));
    }
    // each boss fight's step: what the fight and its portal wait brought
    for (const f of est.fights) {
      const after = Model.estimateAt(est, f.t);
      g.appendChild(svg('text', { x: x(f.t) + 4, y: Math.max(top + 8, y(after.all) + 12), class: 'sp-fight', text: `+${fmtCount(f.spawned)} in the fight` }, svg('title', {}, `the boss fight at ${fmtT(f.t)} (${fmtN(f.seconds, 1)} s, the run clock standing still) and its portal wait (${fmtN(f.portal, 1)} s): +${fmtCount(f.spawned)}${f.minions > 0 ? `, ${fmtCount(f.minions)} of them the boss's own minions` : ''}`)));
    }
    // the arrivals: a crown per Elite, a star per elite modifier, a gear per special, a skull per boss
    for (const m of est.marks) {
      const info = MARKS[m.kind];
      if (!info) continue;
      const p = Model.estimateAt(est, m.t, true);
      const mx = x(m.t), my = Math.max(2, Math.min(bottom - 14, y(p ? p.all : 0) - 15));
      if (info.glyph === 'gear') g.appendChild(svg('path', { d: GEAR, transform: `translate(${mx - 6}, ${my}) scale(0.75)`, fill: info.color, 'fill-rule': 'evenodd', class: 'sp-mark' }));
      else g.appendChild(svg('use', { href: '#g-' + info.glyph, x: mx - 6, y: my, width: 12, height: 12, fill: info.color, class: 'sp-mark' }));
    }
    const shape = Array.isArray(res.opts.turnover) ? (Array.isArray(res.opts.turnover[0]) ? ', minute by minute' : ', stage by stage') : '';
    g.appendChild(svg('text', { x: 48, y: 11, class: 'sp-est', text: `estimate · kill rate from ${App.turnoverSource()}${shape}${res.stale ? ' · updating after the drag' : ''}` }));
    hovers.spawned = (t) => spawnedCard(t);
    s.appendChild(g);
    const SL = App.stageLength();
    const atStage = Model.estimateAt(est, SL, true);
    lanes.spawned.label.querySelector('.lane-sub').textContent = `estimate · ${fmtCount(atStage ? atStage.all : 0)} by ${fmtT(SL)}`;
  }

  /** Which of the card's groups a creature belongs to: a boss, an Elite (the mini-bosses), a special (the specials'
   *  pool) or the regular crowd. */
  function spawnGroup(id) {
    const c = App.creature(id);
    if (c && (c.kind === 'boss' || c.archetype === 'boss')) return 'boss';
    if (c && c.archetype === 'elite') return 'elite';
    const pool = ((App.tl().specials || {}).pool || []).map((r) => (typeof r === 'string' ? r : r && r.enemy));
    if (pool.includes(id)) return 'special';
    return 'regular';
  }

  /** The hover card: the time, every creature spawned by then (the total, each creature largest first with its coloured
   *  share), the Elites, specials and bosses by name, the coloured and elite-modified totals, and the assumptions. */
  function spawnedCard(t) {
    const res = lastSpawn;
    if (!res) return null;
    const est = res.est;
    const p = Model.estimateAt(est, t);
    if (!p) return null;
    const box = el('div', { class: 'sp-card' });
    box.appendChild(el('div', { class: 'hc-head' }, el('b', { text: 'Spawned so far' }), el('span', { class: 'hc-time', text: ` ${fmtT(p.t)} · ${App.stageName(App.stageAt(p.t))} · an estimate${res.stale ? ' (updating after the drag)' : ''}` })));
    box.appendChild(el('div', { class: 'sp-total' }, el('b', { text: fmtCount(p.all) }), ` creatures by ${fmtT(p.t)}`));
    const fight = p.after ? est.fights.find((f) => f.t === p.t) : null;
    if (fight) box.appendChild(el('div', { class: 'hc-line' }, `the boss fight at ${fmtT(fight.t)} (${fmtN(fight.seconds, 1)} s) and its portal wait (${fmtN(fight.portal, 1)} s) brought `, el('b', { text: `+${fmtCount(fight.spawned)}` }), fight.minions > 0 ? `, ${fmtCount(fight.minions)} of them the boss's own minions` : ''));
    const named = (grp) => est.ids.filter((id) => p.by[id] && spawnGroup(id) === grp).map((id) => `${App.creatureName(id)} ${fmtCount(p.by[id][0])}`);
    const swatch = (cls) => el('i', { class: 'sw sp-' + cls });
    const regular = p.reg;
    box.appendChild(el('div', { class: 'sp-cat' }, swatch('plain'), el('b', { text: `Regular ${fmtCount(regular)}` }),
      ' · ', swatch('col'), `coloured ≈ ${fmtCount(p.col)}${regular > 0 ? ` (${fmtN((p.col / regular) * 100, 1)} %)` : ''}`,
      ' · ', swatch('mod'), `elite-modified ≈ ${fmtCount(p.mod)}`, p.minion > 0 ? ` · bosses' minions ${fmtCount(p.minion)}` : ''));
    const others = [['elite', 'Elites', p.elite], ['special', 'Specials', p.special], ['boss', 'Bosses', p.boss]];
    for (const [grp, label, n] of others) {
      const list = named(grp);
      box.appendChild(el('div', { class: 'sp-cat' }, swatch('top'), el('b', { text: `${label} ${fmtCount(n)}` }), list.length ? `: ${list.join(', ')}` : ''));
    }
    const ids = est.ids.filter((id) => p.by[id] && p.by[id][0] > 0.05).sort((a, b) => p.by[b][0] - p.by[a][0]);
    if (ids.length) {
      box.appendChild(el('div', { class: 'ro-title', text: 'every creature, most first · coloured share · elite-modified' }));
      const grid = el('div', { class: 'sp-grid' });
      for (const id of ids) {
        const [n, col, mod] = p.by[id];
        const grp = spawnGroup(id);
        const tag = grp === 'boss' ? 'boss' : grp === 'elite' ? 'Elite' : grp === 'special' ? 'special' : '';
        const colTxt = [col > 0.05 ? `${fmtN((col / n) * 100, 0)} % · ${fmtCount(col)}` : '', mod > 0.05 ? `${fmtCount(mod)} modified` : ''].filter(Boolean).join(' · ');
        grid.appendChild(el('div', { class: 'sp-r' },
          el('img', { src: App.iconFor(id), alt: '' }),
          el('span', { class: 'nm' }, App.creatureName(id), tag ? el('span', { class: 'hc-chip ' + (grp === 'boss' ? 'boss' : grp === 'elite' ? 'elite' : ''), text: tag }) : null),
          el('span', { class: 'n', text: fmtCount(n) }),
          el('span', { class: 'c', text: colTxt })));
      }
      box.appendChild(grid);
    }
    const o = res.opts;
    let tvTxt;
    if (Array.isArray(o.turnover) && Array.isArray(o.turnover[0])) {
      const f = App.S.fit;
      const st = f && Array.isArray(f.by_stage) && f.by_stage.length ? f.by_stage : null;
      tvTxt = `a share of the living crowd each second that changes minute by minute as ${App.turnoverSource()} did${st ? ` (${st.map((v, k) => `${fmtN(v * 100, 1)} % in stage ${k + 1}`).join(', ')} on average)` : ''}`;
    } else if (Array.isArray(o.turnover)) {
      tvTxt = `${o.turnover.map((v, k) => `${fmtN(v * 100, 1)} % in stage ${k + 1}`).join(', ')} of the living crowd a second (${App.turnoverSource()})`;
    } else tvTxt = `${fmtN(o.turnover * 100, 1)} % of the living crowd a second (${App.turnoverSource()})`;
    box.appendChild(el('div', { class: 'sp-note', text: `alive now ≈ ${fmtCount(p.alive)} · killed ≈ ${fmtCount(p.kills)}` }));
    box.appendChild(el('div', { class: 'sp-note', text: `Assumes the hero kills ${tvTxt}, boss fights of ${fmtN(o.bossSeconds, 1)} s and portal waits of ${fmtN(o.portalSeconds, 1)} s; the director refills to the cap under every rule of the timeline. Coloured = the variance specials, once colour_after_kills kills are made.` }));
    return box;
  }

  // ------------------------------------------------------------------ HP x and ATK x (pass 54)

  /** A curve lane: the multiplier the curve gives over the run clock, its points draggable in "points" mode, the formula
   *  drawn in "formula" mode (its saved points faint), the legacy line dashed when the map has no curve. */
  function renderCurve(w, name, key) {
    const s = clear(lanes[name].svg);
    setHeight(name, CURVE_H);
    stageShade(s, CURVE_H);
    const d = App.tl();
    const c = Model.hasCurve(d[key]) ? d[key] : null;
    const mode = c ? Model.curveMode(c) : null;
    const isHp = key === 'hp_curve';
    const f = (t) => (isHp ? App.hpTimeMult(t) : App.dmgTimeMult(t));
    const end = App.viewEnd();
    const pts = c && Array.isArray(c.points) ? c.points : [];
    let maxV = 1.5;
    for (let k = 0; k <= 120; k++) maxV = Math.max(maxV, f(end * k / 120));
    for (const p of pts) maxV = Math.max(maxV, Number(p[1]) || 0);
    maxV *= 1.15;
    const top = 8, bottom = CURVE_H - 10;
    const y = (v) => bottom - (Math.max(0, v) / maxV) * (bottom - top);
    // at most four grid lines, on round multipliers
    const gstep = [0.25, 0.5, 1, 2, 5, 10, 20, 50].find((g) => maxV / g <= 4) || 100;
    for (let v = gstep; v < maxV; v += gstep) {
      s.appendChild(svg('line', { x1: 0, x2: w, y1: y(v), y2: y(v), class: 'grid' + (Math.abs(v - 1) < 1e-9 ? ' one' : '') }));
      s.appendChild(svg('text', { x: 4, y: y(v) - 2, class: 'grid-text', text: `×${fmtN(v, 2)}` }));
    }
    let line = '';
    for (let px = 0; px <= x(end); px += 3) line += `${px},${y(f(px * spp))} `;
    line += `${x(end)},${y(f(end))}`;
    const cls = 'curve-line ' + name + (c ? '' : ' legacy') + (mode === 'formula' ? ' formula' : '') + issueClass(name);
    s.appendChild(svg('polyline', { points: line, class: cls }));
    const what = isHp ? 'HP' : 'damage';
    const hit = svg('polyline', { points: line, class: 'cap-hit' }, svg('title', {}, c
      ? (mode === 'points' ? `The ${what} multiplier over the run clock (manual points): click to edit, double-click to add a point here.` : `The ${what} multiplier over the run clock (a formula): click to edit; switch to manual points in the inspector to drag points.`)
      : `No ${isHp ? 'hp_curve: the legacy hp_growth / hp_power formula' : 'damage_curve: ×1'}. Double-click to start a curve of manual points from this line.`));
    hit.addEventListener('pointerdown', (e) => {
      if (e.button !== 0) return;
      e.stopPropagation();
      if (!isDoubleTap(`curve-line:${name}`, e)) { App.select({ kind: name }); return; }
      e.preventDefault();
      const t = Math.max(0, Math.round(tAt(e.clientX)));
      const r = lanes[name].svg.getBoundingClientRect();
      const v = Math.max(0, Model.round(((bottom - (e.clientY - r.top)) / (bottom - top)) * maxV, 2));
      if (c && mode === 'formula') { App.select({ kind: name }); App.toast(`The ${what} curve is a formula: switch it to manual points in the inspector to add points`); return; }
      App.apply((tl) => {
        if (!Model.hasCurve(tl[key])) {
          // start from the line as it is (the legacy formula, or ×1) at the stage marks, plus the new point
          const SL = App.stageLength(), seeded = [];
          for (let k = 0; k <= App.stages(); k++) seeded.push([k * SL, Model.round(f(k * SL), 4)]);
          tl[key] = isHp
            ? { mode: 'points', points: seeded, formula: { kind: 'power', a: tl.hp_growth == null ? Model.DEF.hp_growth : Number(tl.hp_growth), b: tl.hp_power == null ? Model.DEF.hp_power : Number(tl.hp_power) } }
            : { mode: 'points', points: seeded, formula: { kind: 'linear', a: 0 } };
        }
        if (!Array.isArray(tl[key].points)) tl[key].points = [];
        tl[key].points.push([t, v]);
        App.sortPoints(tl[key].points);
        App.S.sel = { kind: name };
      });
      App.toast(`Added a ${what} point: ${fmtT(t)} → ×${v}`);
    });
    s.appendChild(hit);
    pts.forEach((p, k) => {
      const live = mode === 'points';
      const g = svg('g', { class: 'curve-point ' + name + (live ? '' : ' saved'), transform: `translate(${x(Number(p[0]) || 0)}, ${y(Number(p[1]) || 0)})` },
        svg('title', {}, live ? `${fmtT(p[0])} → ×${p[1]} (drag; double-click to remove)` : `${fmtT(p[0])} → ×${p[1]}: a saved copy (the formula draws the line)`),
        svg('circle', { r: live ? 5.5 : 4 }), svg('text', { x: 7, y: -6, class: 'pt-text', text: `×${fmtN(Number(p[1]), 2)}` }));
      if (live) {
        g.addEventListener('pointerdown', (e) => {
          if (e.button !== 0) return;
          if (!isDoubleTap(`curve-point:${name}:${p[0]}:${p[1]}`, e)) { startDrag(e, { kind: 'curve', key, lane: name, k, y, maxV, top, bottom }); return; }
          e.stopPropagation(); e.preventDefault();
          if (pts.length <= 1) { App.toast('A curve of manual points keeps at least one point (Remove the curve in the inspector to drop it)'); return; }
          App.apply((tl) => { tl[key].points.splice(k, 1); App.S.sel = { kind: name }; });
          App.toast(`Removed a ${what} point`, { undo: true });
        });
      }
      s.appendChild(g);
    });
    if (!c) s.appendChild(svg('text', { x: 48, y: top + 10, class: 'hint-text', text: isHp ? 'legacy: (1 + hp_growth × minutes)^hp_power (double-click the line to start a curve; click for the inspector)' : 'no damage curve: ×1 all run (double-click the line to start one)' }));
    const bd = issueBadge(name, 14, 14);
    if (bd) s.appendChild(bd);
    let sub = !c ? (isHp ? 'legacy hp_growth / hp_power' : 'none: ×1 all run') : mode === 'points' ? `manual · ${plural(pts.length, 'point')}` : 'formula';
    if (c && mode === 'formula') {
      const fk = U.isObj(c.formula) ? (c.formula.kind || 'power') : 'power';
      sub = `formula · ${fk} · a ${fmtN(Model.num(c.formula && c.formula.a, Model.FORMULA_DEF.a), 4)}${fk === 'power' ? ` · b ${fmtN(Model.num(c.formula && c.formula.b, Model.FORMULA_DEF.b), 3)}` : ''}`;
    }
    lanes[name].label.querySelector('.lane-sub').textContent = sub;
  }

  // ------------------------------------------------------------------ roster

  function renderRoster(w) {
    const s = clear(lanes.roster.svg);
    const rows = App.tl().roster || [];
    const h = ROSTER_HEAD + Math.max(1, rows.length) * ROW_H + PAD;
    setHeight('roster', h);
    const end = App.viewEnd();
    stageShade(s, h);
    // one weight scale for every row, so their areas compare (held while a presence point is dragged)
    let maxW = 1;
    for (const r of rows) {
      if (Array.isArray(r.weights) && r.weights.length) for (const p of r.weights) maxW = Math.max(maxW, Number(p[1]) || 0);
      else maxW = Math.max(maxW, App.rowWeight(r, Number(r.t) || 0));
    }
    if (frozenMax != null) maxW = frozenMax;
    s.appendChild(svg('text', { x: 6, y: 25, class: 'hint-text', text: `a bar's filled height is its presence weight (full bar = ${fmtN(maxW, 2)}); drag a point, double-click the bar to add one, a point to remove it` }));
    const bh = ROW_H - 6, span = bh - 6;
    rows.forEach((r, i) => {
      const key = `roster:${i}`;
      const t = Number(r.t) || 0;
      const open = r.until == null || r.until === '';
      const until = open ? end : Number(r.until);
      const tEnd = Math.max(t, Math.min(until, end));
      const x0 = x(t), x1 = Math.max(x0 + 4, x(tEnd));
      const y0 = ROSTER_HEAD + i * ROW_H + 3;
      const c = App.creature(r.enemy);
      const col = App.creatureColor(r.enemy);
      const yb = y0 + bh - 3;
      const yW = (v) => yb - (Math.max(0, v) / maxW) * span;
      const g = svg('g', { class: 'bar' + (r.channel === 'hell' ? ' hell' : '') + (App.selKey() === key ? ' selected' : '') + issueClass(key), 'data-key': key, 'data-hover': key });
      g.appendChild(svg('rect', { x: x0, y: y0, width: x1 - x0, height: bh, rx: 4, class: 'bar-body' }));
      const clipId = `clip-r${i}`;
      g.appendChild(svg('clipPath', { id: clipId }, svg('rect', { x: x0, y: y0, width: Math.max(0, x1 - x0), height: bh })));
      const inner = svg('g', { 'clip-path': `url(#${clipId})` });
      // the presence area: the weight curve inside the bar, a vertex at each keyframe
      const ws = Array.isArray(r.weights) && r.weights.length ? r.weights.map((p, k) => ({ t: Number(p[0]) || 0, w: Number(p[1]) || 0, k })).sort((a, b) => a.t - b.t || a.k - b.k) : [];
      const verts = [[x0, yW(App.rowWeight(r, t))]];
      for (const p of ws) if (p.t > t && p.t < tEnd) verts.push([x(p.t), yW(p.w)]);
      verts.push([x(tEnd), yW(App.rowWeight(r, tEnd))]);
      inner.appendChild(svg('path', { d: `M${x0},${yb} ${verts.map(([vx, vy]) => `L${vx},${vy}`).join(' ')} L${x(tEnd)},${yb} Z`, class: 'w-area', fill: col }));
      inner.appendChild(svg('polyline', { points: verts.map(([vx, vy]) => `${vx},${vy}`).join(' '), class: 'w-edge', stroke: col }));
      if (c) inner.appendChild(svg('image', { href: App.iconFor(r.enemy, r.variant), x: x0 + 3, y: y0 + 1.5, width: 17, height: 17, preserveAspectRatio: 'xMidYMid meet' }));
      let tx = x0 + 24;
      inner.appendChild(svg('text', { x: tx, y: y0 + 13, class: 'bar-text', text: App.creatureName(r.enemy) }));
      tx += textWidth(App.creatureName(r.enemy), 12) + 8;
      const first = ws.length ? ws[0].w : App.rowWeight(r, t), last = ws.length ? ws[ws.length - 1].w : first;
      const wt = ws.length > 2 ? `w ${fmtN(first)} → … → ${fmtN(last)}` : first !== last ? `w ${fmtN(first)} → ${fmtN(last)}` : `w ${fmtN(first)}`;
      inner.appendChild(svg('text', { x: tx, y: y0 + 13, class: 'bar-sub', text: wt }));
      tx += textWidth(wt, 11) + 8;
      const chips = [];
      if (r.variant) chips.push({ text: r.variant, cls: 'chip-variant' });
      if (r.pack != null) chips.push({ text: `×${r.pack}`, cls: 'chip-pack' });
      if (r.pattern && r.pattern !== 'pack') chips.push({ text: patternLabel(r.pattern), cls: 'chip-pattern' });
      if (r.stats && Object.keys(r.stats).length) chips.push({ glyph: 'wrench', cls: 'chip-wrench' });
      for (const ch of chips) tx = chip(inner, tx, y0 + 2, ch);
      g.appendChild(inner);
      if (open) g.appendChild(svg('text', { x: x1 - 12, y: y0 + 14, class: 'inf', text: '∞' }));
      // keyframes outside the bar (the row ends before them, or starts after them): a faint dashed tail, still draggable
      const after = ws.filter((p) => p.t > tEnd);
      if (after.length && !open) g.appendChild(svg('polyline', { points: [[x1, yW(App.rowWeight(r, tEnd))], ...after.map((p) => [x(p.t), yW(p.w)])].map(([a, b]) => `${a},${b}`).join(' '), class: 'w-ghost', stroke: col }));
      const before = ws.filter((p) => p.t < t);
      if (before.length) g.appendChild(svg('polyline', { points: [...before.map((p) => [x(p.t), yW(p.w)]), [x0, yW(App.rowWeight(r, t))]].map(([a, b]) => `${a},${b}`).join(' '), class: 'w-ghost', stroke: col }));
      const handle = svg('rect', { x: x1 - HANDLE, y: y0, width: HANDLE, height: bh, class: 'handle' });
      handle.appendChild(svg('title', {}, open ? 'drag to give the row an end' : 'drag to move the end'));
      handle.addEventListener('pointerdown', (e) => startDrag(e, { kind: 'roster', i, mode: 'until' }));
      g.addEventListener('pointerdown', (e) => {
        if (e.button !== 0) return;
        if (isDoubleTap(`rbar:${i}`, e)) { e.stopPropagation(); e.preventDefault(); addPresencePoint(i, e, { yb, span, maxW }); return; }
        startDrag(e, { kind: 'roster', i, mode: 'move' });
      });
      g.appendChild(handle);
      // the keyframes themselves, above everything in the bar
      if (Array.isArray(r.weights)) {
        r.weights.forEach((p, k) => {
          const pt = Number(p[0]) || 0, pw = Number(p[1]) || 0;
          const out = pt < t || pt > tEnd;
          const dot = svg('g', { class: 'w-pt' + (out ? ' ghost' : ''), transform: `translate(${x(pt)}, ${yW(pw)})` },
            svg('circle', { r: 4.5, fill: col }), svg('text', { x: 6, y: -4, class: 'w-pt-text', text: fmtN(pw, 2) }));
          dot.addEventListener('pointerdown', (e) => {
            if (e.button !== 0) return;
            e.stopPropagation();
            if (!isDoubleTap(`wpt:${i}:${k}`, e)) { startDrag(e, { kind: 'weight', i, k, maxW, span }); return; }
            e.preventDefault();
            if (r.weights.length <= 2) { App.toast('A row keeps at least two presence points'); return; }
            App.apply((tl) => { tl.roster[i].weights.splice(k, 1); App.S.sel = { kind: 'roster', i }; });
            App.toast('Removed a presence point', { undo: true });
          });
          g.appendChild(dot);
        });
      }
      const b = issueBadge(key, x0 + 1, y0 + 1);
      if (b) g.appendChild(b);
      hovers[key] = (tt) => rosterCard(i, tt);
      s.appendChild(g);
    });
    if (!rows.length) s.appendChild(svg('text', { x: 8, y: ROSTER_HEAD + 18, class: 'hint-text', text: 'no roster rows: "+ Row" adds one at the view\'s centre' }));
    lanes.roster.label.querySelector('.lane-sub').textContent = `${plural(rows.length, 'row')} · ${rows.filter((r) => r.channel === 'hell').length} hell`;
    renderGutter(rows);
  }

  /** A presence keyframe where the double-click landed: its time, and the weight its height on the bar says. */
  function addPresencePoint(i, e, sc) {
    const r = (App.tl().roster || [])[i];
    if (!r) return;
    const t = Math.max(0, Math.round(tAt(e.clientX)));
    const top = lanes.roster.svg.getBoundingClientRect().top;
    const w = Math.max(0, Model.round(((sc.yb - (e.clientY - top)) / sc.span) * sc.maxW, 1));
    App.apply((tl) => {
      const row = tl.roster[i];
      if (!Array.isArray(row.weights) || !row.weights.length) row.weights = Model.keyframesOf(row, tl.weight_late_t);
      row.weights.push([t, w]);
      App.sortPoints(row.weights);
      App.S.sel = { kind: 'roster', i };
    });
    App.toast(`Added a presence point: ${fmtT(t)} → weight ${w}`);
  }

  /** The roster's gutter in the sticky label column: per row a grip to drag it up or down, ▲ / ▼, its icon and name (a
   *  click selects the row). The order is for this page only: the game draws by weight. */
  function renderGutter(rows) {
    const gut = lanes.roster.label.querySelector('.gutter');
    clear(gut);
    rows.forEach((r, i) => {
      const sel = App.selKey() === `roster:${i}`;
      const grip = el('span', { class: 'grip', title: 'drag up or down to reorder (the order is for this page only)', text: '⠿' });
      grip.addEventListener('pointerdown', (e) => startReorder(e, i, rows.length));
      const pick = () => App.select({ kind: 'roster', i }, { scroll: true });
      gut.appendChild(el('div', { class: 'gut-row' + (sel ? ' selected' : '') + (r.channel === 'hell' ? ' hell' : ''), style: `top:${ROSTER_HEAD + i * ROW_H}px;height:${ROW_H}px` },
        grip,
        el('button', { class: 'gut-btn', type: 'button', text: '▲', title: 'move up (Alt+↑)', disabled: i === 0, onclick: (e) => { e.stopPropagation(); App.moveRow(i, -1); } }),
        el('button', { class: 'gut-btn', type: 'button', text: '▼', title: 'move down (Alt+↓)', disabled: i === rows.length - 1, onclick: (e) => { e.stopPropagation(); App.moveRow(i, 1); } }),
        el('img', { src: App.iconFor(r.enemy, r.variant), width: 18, height: 18, alt: '', onclick: pick }),
        el('span', { class: 'gut-name', text: App.creatureName(r.enemy), title: `${App.creatureName(r.enemy)}${r.id ? ` (${r.id})` : ''}: click to select`, onclick: pick })));
    });
  }

  /** Drag a row's grip: a line shows where it lands, the drop moves it there. */
  function startReorder(e, from, n) {
    if (e.button !== 0) return;
    e.preventDefault(); e.stopPropagation();
    hideCard();
    const lane = lanes.roster.row;
    const line = el('div', { class: 'reorder-line' });
    lane.appendChild(line);
    let to = from;
    document.body.classList.add('dragging');
    const move = (ev) => {
      const yy = ev.clientY - lane.getBoundingClientRect().top - ROSTER_HEAD;
      to = Math.max(0, Math.min(n, Math.round(yy / ROW_H)));
      line.style.top = `${ROSTER_HEAD + to * ROW_H - 1}px`;
    };
    const up = () => {
      window.removeEventListener('pointermove', move);
      document.body.classList.remove('dragging');
      line.remove();
      const dest = to > from ? to - 1 : to;
      if (dest !== from) App.moveRowTo(from, dest);
    };
    move(e);
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up, { once: true });
  }

  /** A shaded strip per stage behind a lane (stage 2 and 3 slightly darker), so the eye keeps the stage while scrolling. */
  function stageShade(s, h) {
    const SL = App.stageLength(), n = App.stages();
    for (let k = 1; k < n; k += 2) s.appendChild(svg('rect', { x: x(k * SL), y: 0, width: x(SL), height: h, class: 'stage-shade' }));
    s.appendChild(svg('rect', { x: x(App.runEnd()), y: 0, width: x(App.viewEnd()) - x(App.runEnd()) + 60, height: h, class: 'endless-shade' }));
    for (let k = 1; k <= n; k++) s.appendChild(svg('line', { x1: x(k * SL), x2: x(k * SL), y1: 0, y2: h, class: 'stage-line' }));
  }

  function textWidth(str, px) { return String(str).length * px * 0.56; }

  const plural = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`;

  function chip(parent, tx, ty, ch) {
    const w = ch.glyph ? 20 : textWidth(ch.text, 10) + 10;
    const g = svg('g', { class: 'chip ' + (ch.cls || '') });
    if (ch.title) g.appendChild(svg('title', {}, ch.title));
    g.appendChild(svg('rect', { x: tx, y: ty, width: w, height: 15, rx: 7 }));
    if (ch.glyph) g.appendChild(svg('use', { href: '#g-' + ch.glyph, x: tx + 3, y: ty + 0.5, width: 14, height: 14 }));
    else g.appendChild(svg('text', { x: tx + 5, y: ty + 11, class: 'chip-text', text: ch.text }));
    parent.appendChild(g);
    return tx + w + 5;
  }

  // ------------------------------------------------------------------ share (pass 54)

  /** Each creature's share of its channel's draw over time, stacked (regular crowd above, the hell channel below), one
   *  colour per creature; the legend is the creatures' icons in the label column. */
  function renderShare(w) {
    const s = clear(lanes.share.svg);
    const rows = App.tl().roster || [];
    const order = { reg: [], hell: [] };
    for (const r of rows.map((r, i) => ({ r, i })).sort((a, b) => (Number(a.r.t) || 0) - (Number(b.r.t) || 0) || a.i - b.i)) {
      const ch = r.r.channel === 'hell' ? 'hell' : 'reg';
      if (!order[ch].includes(r.r.enemy)) order[ch].push(r.r.enemy);
    }
    const legendN = order.reg.length + order.hell.length;
    const hasHell = order.hell.length > 0;
    const REG = 58, HELL = hasHell ? 32 : 0, GAP = hasHell ? 5 : 0;
    const need = 26 + Math.ceil(legendN / 6) * 22;
    const h = Math.max(6 + REG + GAP + HELL + 6, need);
    setHeight('share', h);
    stageShade(s, h);
    const end = App.viewEnd();
    const bands = [{ ch: 'reg', top: 6, H: REG }];
    if (hasHell) bands.push({ ch: 'hell', top: 6 + REG + GAP, H: HELL });
    const g = svg('g', { class: 'share' + (App.selKey() === 'share' ? ' selected' : ''), 'data-hover': 'share' });
    for (const b of bands) {
      g.appendChild(svg('rect', { x: 0, y: b.top, width: w, height: b.H, class: 'share-bg' + (b.ch === 'hell' ? ' hell' : '') }));
      const ids = order[b.ch];
      const acc = ids.map(() => []);
      const step = 3;
      for (let px = 0; px <= x(end) + step; px += step) {
        const t = Math.min(end, px * spp);
        const by = {};
        for (const o of App.rosterAt(t)) if ((o.hell ? 'hell' : 'reg') === b.ch) by[o.row.enemy] = (by[o.row.enemy] || 0) + o.norm;
        let yb = b.top + b.H;
        ids.forEach((id, k) => { const yt = yb - (by[id] || 0) * b.H; acc[k].push([Math.min(px, x(end)), yb, yt]); yb = yt; });
      }
      ids.forEach((id, k) => {
        const pts = acc[k];
        if (!pts.some(([, y0, y1]) => y0 - y1 > 0.05)) return;
        const d = pts.map(([px, , yt]) => `${px},${yt}`).join(' ') + ' ' + pts.slice().reverse().map(([px, yb]) => `${px},${yb}`).join(' ');
        g.appendChild(svg('polygon', { points: d, fill: App.creatureColor(id), class: 'share-area' }));
      });
      g.appendChild(svg('text', { x: 4, y: b.top + 10, class: 'share-tag', text: b.ch === 'hell' ? 'hell' : 'regular' }));
    }
    g.addEventListener('pointerdown', (e) => { if (e.button === 0) { e.stopPropagation(); App.select({ kind: 'share' }); } });
    hovers.share = (t) => shareCard(t);
    s.appendChild(g);
    // the legend: the creatures' icons over their colours
    const lg = lanes.share.label.querySelector('.share-legend');
    clear(lg);
    for (const ch of ['reg', 'hell']) for (const id of order[ch]) {
      lg.appendChild(el('span', { class: 'lg' + (ch === 'hell' ? ' hell' : ''), title: `${App.creatureName(id)}${ch === 'hell' ? ' (hell channel)' : ''}` },
        el('img', { src: App.iconFor(id), width: 18, height: 18, alt: '' }), el('i', { style: `background:${App.creatureColor(id)}` })));
    }
    lanes.share.label.querySelector('.lane-sub').textContent = `${order.reg.length} creatures${hasHell ? ` + ${order.hell.length} hell` : ''}`;
  }

  // ------------------------------------------------------------------ waves

  function renderWaves(w) {
    const s = clear(lanes.waves.svg);
    const waves = App.tl().waves || [];
    const end = App.viewEnd();
    // pack the blocks into tracks so overlapping waves sit under each other
    const blocks = waves.map((wv, i) => {
      const t = Number(wv.t) || 0, e = App.waveEnd(wv);
      const alts = App.waveAlts(wv);
      return { wv, i, t, e, x0: x(t), x1: Math.max(x(t) + 6, x(Math.min(e, end))), h: 22 + 14 * alts.length, alts, forever: e === Infinity };
    });
    const order = blocks.slice().sort((a, b) => a.t - b.t || a.i - b.i);
    const tracks = [];
    for (const b of order) {
      let k = tracks.findIndex((tr) => tr.right + 3 <= b.x0);
      if (k < 0) { tracks.push({ right: -1, h: 0, blocks: [] }); k = tracks.length - 1; }
      tracks[k].right = b.x1; tracks[k].h = Math.max(tracks[k].h, b.h); tracks[k].blocks.push(b); b.track = k;
    }
    let y = PAD;
    for (const tr of tracks) { tr.y = y; y += tr.h + PAD; }
    const h = Math.max(ROW_H + PAD * 2 + 20, y);
    setHeight('waves', h);
    stageShade(s, h);
    for (const b of blocks) {
      const key = `wave:${b.i}`;
      const wv = b.wv;
      const y0 = tracks[b.track].y;
      const g = svg('g', { class: 'block' + (App.selKey() === key ? ' selected' : '') + (wv.respect_cap === false ? ' nocap' : '') + (wv.channel === 'hell' ? ' hell' : '') + issueClass(key), 'data-key': key, 'data-hover': key });
      const head = waveHead(wv);
      g.appendChild(svg('rect', { x: b.x0, y: y0, width: b.x1 - b.x0, height: b.h, rx: 5, class: 'block-body' + (b.forever ? ' forever' : '') }));
      const clipId = `clip-w${b.i}`;
      g.appendChild(svg('clipPath', { id: clipId }, svg('rect', { x: b.x0, y: y0, width: Math.max(0, b.x1 - b.x0 - 4), height: b.h })));
      const inner = svg('g', { 'clip-path': `url(#${clipId})` });
      const wide = b.x1 - b.x0 > 90;
      if (wide) {
        let tx = b.x0 + 6;
        inner.appendChild(svg('text', { x: tx, y: y0 + 14, class: 'block-head', text: head }));
        tx += textWidth(head, 11.5) + 8;
        if (wv.respect_cap === false) tx = chip(inner, tx, y0 + 3, { text: 'no cap', cls: 'chip-nocap' });
        if (wv.elite) tx = chip(inner, tx, y0 + 3, { glyph: 'crown', cls: 'chip-crown' });
        if (wv.channel === 'hell') tx = chip(inner, tx, y0 + 3, { text: 'hell', cls: 'chip-hell' });
        if (wv.pattern && wv.pattern !== 'pack') tx = chip(inner, tx, y0 + 3, { text: patternLabel(wv.pattern), cls: 'chip-pattern' });
        if (wv.toast) tx = chip(inner, tx, y0 + 3, { text: `“${wv.toast}”`, cls: 'chip-toast' });
      }
      b.alts.forEach((a, k) => {
        const sy = y0 + 20 + k * 14;
        const c = App.creature(a.alt.enemy);
        const hk = `alt:${b.i}:${k}`;
        const stripe = svg('g', { class: 'stripe', 'data-hover': hk });
        stripe.appendChild(svg('rect', { x: b.x0 + 2, y: sy, width: Math.max(0, b.x1 - b.x0 - 4), height: 13, rx: 2, fill: ALT_COLORS[k % ALT_COLORS.length], opacity: 0.55 }));
        if (c) stripe.appendChild(svg('image', { href: App.iconFor(a.alt.enemy, a.alt.variant), x: b.x0 + 4, y: sy, width: 13, height: 13, preserveAspectRatio: 'xMidYMid meet' }));
        if (wide) {
          const txt = `${Math.round(a.share * 100)}% ${App.creatureName(a.alt.enemy)}${a.alt.variant ? ' ' + a.alt.variant : ''}${a.alt.pack != null ? ' ×' + a.alt.pack : ''}${a.alt.stats && Object.keys(a.alt.stats).length ? '  ' + overridesShort(a.alt.stats) : ''}`;
          stripe.appendChild(svg('text', { x: b.x0 + 20, y: sy + 10, class: 'stripe-text', text: txt }));
        }
        hovers[hk] = (tt) => altCard(b.i, k, tt);
        inner.appendChild(stripe);
      });
      g.appendChild(inner);
      if (!wide) g.appendChild(svg('text', { x: b.x1 + 4, y: y0 + 14, class: 'block-out', text: head }));
      const handle = svg('rect', { x: b.x1 - HANDLE, y: y0, width: HANDLE, height: b.h, class: 'handle' });
      handle.appendChild(svg('title', {}, 'drag to set `until`'));
      handle.addEventListener('pointerdown', (e) => startDrag(e, { kind: 'wave', i: b.i, mode: 'until' }));
      g.addEventListener('pointerdown', (e) => startDrag(e, { kind: 'wave', i: b.i, mode: 'move' }));
      g.appendChild(handle);
      const bd = issueBadge(key, b.x0 + 1, y0 + 1);
      if (bd) g.appendChild(bd);
      hovers[key] = (tt) => waveCard(b.i, tt);
      s.appendChild(g);
    }
    if (!waves.length) s.appendChild(svg('text', { x: 8, y: 24, class: 'hint-text', text: 'no waves yet: "+ Wave" adds one at the view\'s centre, or pick a creature on the Creatures tab' }));
    lanes.waves.label.querySelector('.lane-sub').textContent = plural(waves.length, 'wave');
  }

  function waveHead(wv) {
    const cnt = Number(wv.count) || 0, burst = wv.burst == null ? 5 : wv.burst, every = wv.every == null ? 2 : wv.every;
    return `${wv.name || wv.id || 'wave'} · ${cnt > 0 ? cnt : '∞'} in ${burst}s every ${fmtN(every)} s`;
  }

  function overridesShort(st) {
    const parts = [];
    for (const [k, v] of Object.entries(st)) {
      if (typeof v === 'object') parts.push(k);
      else parts.push(`${k} ${v}`);
    }
    return parts.slice(0, 4).join(', ') + (parts.length > 4 ? ' …' : '');
  }

  // ------------------------------------------------------------------ events

  function renderEvents(w) {
    const s = clear(lanes.events.svg);
    setHeight('events', EV_H);
    const evs = (App.tl().events || []).map((ev, i) => ({ ev, i, t: Number(ev.t) || 0 })).sort((a, b) => a.t - b.t || a.i - b.i);
    stageShade(s, EV_H);
    const end = App.viewEnd();
    const levelRight = [-1e9, -1e9, -1e9];
    for (const e of evs) {
      const key = `event:${e.i}`;
      const info = FIELDS.EVENT_TYPES[e.ev.type] || { glyph: 'star', color: '#888', label: e.ev.type };
      const px = x(e.t);
      const label = App.eventLabel(e.ev);
      const lw = textWidth(label, 11) + 24;
      let lvl = levelRight.findIndex((r) => r <= px - 6);
      if (lvl < 0) { lvl = levelRight.indexOf(Math.min(...levelRight)); }
      levelRight[lvl] = px + lw;
      const cy = 16 + lvl * 26;
      const faded = e.ev.chance != null && Number(e.ev.chance) < 1;
      const g = svg('g', { class: 'marker' + (App.selKey() === key ? ' selected' : '') + (faded ? ' faded' : '') + issueClass(key), 'data-key': key, 'data-hover': key });
      if (e.ev.type === 'elite_every') {
        const iv = e.ev.interval;
        const lo = Array.isArray(iv) ? Number(iv[0]) : Number(iv == null ? 90 : iv);
        const hi = Array.isArray(iv) ? Number(iv[iv.length - 1]) : lo;
        const mean = Math.max(1, (lo + hi) / 2);
        g.appendChild(svg('line', { x1: px, x2: x(end) + 40, y1: cy, y2: cy, class: 'repeat-line' }));
        let n = 0;
        for (let t = e.t + mean; t <= end && n < 400; t += mean, n++) g.appendChild(svg('line', { x1: x(t), x2: x(t), y1: cy - 4, y2: cy + 4, class: 'repeat-tick' }));
      }
      const j = Number(e.ev.t_jitter) || 0;
      if (j > 0) {
        g.appendChild(svg('line', { x1: x(e.t - j), x2: x(e.t + j), y1: cy, y2: cy, class: 'whisker' }));
        g.appendChild(svg('line', { x1: x(e.t - j), x2: x(e.t - j), y1: cy - 5, y2: cy + 5, class: 'whisker' }));
        g.appendChild(svg('line', { x1: x(e.t + j), x2: x(e.t + j), y1: cy - 5, y2: cy + 5, class: 'whisker' }));
      }
      g.appendChild(svg('line', { x1: px, x2: px, y1: cy, y2: EV_H, class: 'drop-line' }));
      g.appendChild(svg('rect', { x: px - 10, y: cy - 10, width: 20, height: 20, rx: 5, class: 'marker-bg' }));
      g.appendChild(svg('use', { href: '#g-' + info.glyph, x: px - 8, y: cy - 8, width: 16, height: 16, fill: info.color }));
      g.appendChild(svg('text', { x: px + 13, y: cy + 4, class: 'marker-text', text: label + (faded ? `  ${Math.round(Number(e.ev.chance) * 100)}%` : '') }));
      const ids = U.idList(e.ev.enemy);
      ids.slice(0, 4).forEach((id, k) => {
        const c = App.creature(id);
        if (c) g.appendChild(svg('image', { href: App.iconFor(id, e.ev.variant), x: px + 14 + lw - 24 + k * 15, y: cy - 7, width: 14, height: 14, preserveAspectRatio: 'xMidYMid meet', opacity: 0.9 }));
      });
      g.addEventListener('pointerdown', (ev) => startDrag(ev, { kind: 'event', i: e.i, mode: 'move' }));
      const bd = issueBadge(key, px - 10, cy - 10);
      if (bd) g.appendChild(bd);
      hovers[key] = () => eventCard(e.i);
      s.appendChild(g);
    }
    lanes.events.label.querySelector('.lane-sub').textContent = plural(evs.length, 'event');
  }

  // ------------------------------------------------------------------ specials and paths

  function renderSpecials(w) {
    const s = clear(lanes.specials.svg);
    setHeight('specials', SP_H);
    stageShade(s, SP_H);
    const sp = App.tl().specials;
    const key = 'specials';
    if (!sp || !Object.keys(sp).length) {
      s.appendChild(svg('text', { x: 8, y: 25, class: 'hint-text', text: 'no specials on this map (Settings → Specials)' }));
      lanes.specials.label.querySelector('.lane-sub').textContent = 'none';
      return;
    }
    const from = Number(sp.from == null ? App.stageLength() * 0.5 : sp.from);
    const iv = Array.isArray(sp.interval) ? sp.interval : [20, 40];
    const pool = sp.pool || [];
    const g = svg('g', { class: 'special-band' + (App.selKey() === key ? ' selected' : '') + issueClass(key), 'data-key': key, 'data-hover': key, onpointerdown: (e) => { if (e.button === 0) { e.stopPropagation(); App.select({ kind: 'specials' }); } } });
    g.appendChild(svg('rect', { x: x(from), y: 8, width: x(App.viewEnd()) - x(from) + 60, height: 26, rx: 5, class: 'band-body' }));
    let tx = x(from) + 6;
    for (const row of pool) {
      const id = typeof row === 'string' ? row : row.enemy;
      const st = typeof row === 'string' ? 1 : Number(row.stage || 1);
      const c = App.creature(id);
      if (c) g.appendChild(svg('image', { href: App.iconFor(id), x: tx, y: 11, width: 20, height: 20, preserveAspectRatio: 'xMidYMid meet' }));
      if (st > 1) g.appendChild(svg('text', { x: tx + 14, y: 32, class: 'stage-tag', text: `S${st}` }));
      tx += 26;
    }
    g.appendChild(svg('text', { x: tx + 4, y: 25, class: 'bar-text', text: `from ${fmtT(from)}: ${sp.max_alive || 1} at a time, the next ${iv[0]}–${iv[iv.length - 1]} s after the last dies` }));
    const bd = issueBadge(key, x(from) + 1, 9);
    if (bd) g.appendChild(bd);
    hovers.specials = (t) => specialsCard(t);
    s.appendChild(g);
    lanes.specials.label.querySelector('.lane-sub').textContent = `${pool.length} in the pool`;
  }

  function renderPaths(w) {
    const s = clear(lanes.paths.svg);
    setHeight('paths', PATH_H);
    stageShade(s, PATH_H);
    const pt = App.tl().path_times || [];
    const SL = App.stageLength();
    const key = 'paths';
    const g = svg('g', { class: 'paths' + (App.selKey() === key ? ' selected' : '') + issueClass(key), 'data-key': key, onpointerdown: (e) => { if (e.button === 0) { e.stopPropagation(); App.select({ kind: 'paths' }); } } });
    g.appendChild(svg('rect', { x: 0, y: 0, width: w, height: PATH_H, class: 'paths-hit' }));
    let n = 0;
    for (let st = 0; st < App.stages() && pt.length; st++) {
      const list = pt[Math.min(st, pt.length - 1)] || [];
      list.forEach((v, k) => {
        const px = x(st * SL + Number(v));
        g.appendChild(svg('line', { x1: px, x2: px, y1: 6, y2: 20, class: 'path-tick' }));
        g.appendChild(svg('text', { x: px + 2, y: 29, class: 'path-text', text: k + 1 }));
        n++;
      });
    }
    if (!pt.length) g.appendChild(svg('text', { x: 8, y: 20, class: 'hint-text', text: 'no path offers (Settings → Items)' }));
    const bd = issueBadge(key, 10, 10);
    if (bd) g.appendChild(bd);
    s.appendChild(g);
    lanes.paths.label.querySelector('.lane-sub').textContent = plural(n, 'offer');
  }

  // ------------------------------------------------------------------ drag

  function startDrag(e, spec) {
    if (e.button !== 0) return;
    e.stopPropagation();
    e.preventDefault();
    hideCard();
    const tl = App.tl();
    const item = spec.kind === 'roster' || spec.kind === 'weight' ? tl.roster[spec.i] : spec.kind === 'wave' ? tl.waves[spec.i] : spec.kind === 'event' ? tl.events[spec.i] : null;
    const pair = (p) => [Number(p[0]) || 0, Number(p[1]) || 0];
    drag = {
      spec, x0: e.clientX, y0: e.clientY, moved: false, before: App.snapshot(),
      t0: item ? Number(item.t) || 0 : 0,
      until0: item && item.until != null && item.until !== '' ? Number(item.until) : null,
      end0: item && spec.kind === 'wave' ? App.waveEnd(item) : null,
      p0: spec.kind === 'cap' ? pair(tl.cap_curve[spec.k]) : spec.kind === 'curve' ? pair(tl[spec.key].points[spec.k]) : spec.kind === 'weight' ? pair(item.weights[spec.k]) : null,
      w0: spec.kind === 'roster' && item && Array.isArray(item.weights) ? item.weights.map(pair) : null,
    };
    if (spec.kind === 'weight') frozenMax = spec.maxW;
    document.body.classList.add('dragging');
    window.addEventListener('pointermove', onDragMove);
    window.addEventListener('pointerup', onDragUp, { once: true });
  }

  function onDragMove(e) {
    if (!drag) return;
    const dx = e.clientX - drag.x0;
    if (!drag.moved && Math.abs(dx) < 3 && Math.abs(e.clientY - drag.y0) < 3) return;
    drag.moved = true;
    const dt = Math.round(dx * spp);
    const tl = App.tl();
    const sp = drag.spec;
    if (sp.kind === 'cap' || sp.kind === 'curve') {
      const p = sp.kind === 'cap' ? tl.cap_curve[sp.k] : tl[sp.key].points[sp.k];
      p[0] = Math.max(0, drag.p0[0] + dt);
      const dv = -((e.clientY - drag.y0) / (sp.bottom - sp.top)) * sp.maxV;
      p[1] = sp.kind === 'cap' ? Math.max(0, Math.round(drag.p0[1] + dv)) : Math.max(0, Model.round(drag.p0[1] + dv, 2));
      render();
      App.setClock(p[0], sp.kind === 'cap' ? `cap ${p[1]}` : `×${p[1]}`);
      return;
    }
    if (sp.kind === 'weight') {
      const p = tl.roster[sp.i].weights[sp.k];
      p[0] = Math.max(0, drag.p0[0] + dt);
      const dw = -((e.clientY - drag.y0) / sp.span) * sp.maxW;
      p[1] = Math.max(0, Model.round(drag.p0[1] + dw, 1));
      render();
      App.setClock(p[0], `weight ${p[1]}`);
      return;
    }
    const item = sp.kind === 'roster' ? tl.roster[sp.i] : sp.kind === 'wave' ? tl.waves[sp.i] : tl.events[sp.i];
    if (!item) return;
    if (sp.mode === 'move') {
      const nt = Math.max(0, drag.t0 + dt);
      item.t = nt;
      if (drag.until0 != null) item.until = Math.max(nt + 1, drag.until0 + (nt - drag.t0));
      // a roster row's presence keyframes are run-clock times: they travel with the bar
      if (sp.kind === 'roster' && drag.w0) item.weights = drag.w0.map(([pt, pv]) => [Math.max(0, pt + (nt - drag.t0)), pv]);
    } else {
      const base = drag.until0 != null ? drag.until0 : (drag.end0 != null && drag.end0 !== Infinity ? Math.round(drag.end0) : Math.round(tAt(drag.x0)));
      item.until = Math.max((Number(item.t) || 0) + 1, Math.round(base + dt));
    }
    render();
    App.setClock(sp.mode === 'until' ? Number(item.until) : Number(item.t), sp.mode === 'until' ? 'until' : 'from');
  }

  function onDragUp() {
    window.removeEventListener('pointermove', onDragMove);
    document.body.classList.remove('dragging');
    if (!drag) return;
    const d = drag; drag = null;
    frozenMax = null;
    const sp = d.spec;
    const sel = sp.kind === 'cap' ? { kind: 'cap' } : sp.kind === 'curve' ? { kind: sp.lane } : sp.kind === 'weight' ? { kind: 'roster', i: sp.i } : { kind: sp.kind, i: sp.i };
    if (d.moved) {
      const tl = App.tl();
      if (sp.kind === 'cap') App.sortPoints(tl.cap_curve);
      if (sp.kind === 'curve') App.sortPoints(tl[sp.key].points);
      if (sp.kind === 'weight') App.sortPoints(tl.roster[sp.i].weights);
      App.S.sel = sel;
      App.pushHistory(d.before);
      App.render('all');
    } else {
      App.select(sel);
    }
  }

  // ------------------------------------------------------------------ hover cards (pass 54)

  function hideCard() { if (card) card.hidden = true; }

  function place(box, cx, cy) {
    const r = box.getBoundingClientRect();
    let left = cx + 18, top = cy + 18;
    if (left + r.width > window.innerWidth - 8) left = cx - r.width - 12;
    if (top + r.height > window.innerHeight - 8) top = Math.max(8, window.innerHeight - r.height - 8);
    box.style.left = `${Math.max(4, left)}px`;
    box.style.top = `${top}px`;
  }

  /** "HP 39 · ATK 5" for one creature at t with the row's overrides: an orange dot before a number an override changed,
   *  `*` after the pair when other stats are overridden (listed on the next line), the factors on a muted line. */
  function creatureBlock(id, variant, stats, t, opts) {
    const o = opts || {};
    const c = App.creature(id);
    if (!c) return el('div', { class: 'hc-line bad', text: `unknown creature "${id || ''}"` });
    const st = U.isObj(stats) ? stats : {};
    const at = App.creatureAt(c, st, t);
    const setHp = st.hp != null || st.hp_mult != null || (at.arch === 'elite' && U.getPath(st, 'elite.hp_mult_per_stage') != null) || (at.arch === 'boss' && U.getPath(st, 'boss.hp_mult_per_stage') != null);
    const setAtk = st.damage != null || st.damage_mult != null;
    const others = Model.otherOverrides(st).filter((s) => !(at.arch === 'elite' && s.startsWith('elite.hp_mult_per_stage')) && !(at.arch === 'boss' && s.startsWith('boss.hp_mult_per_stage')));
    const dot = (on) => (on ? el('span', { class: 'hc-dot', title: 'an override changes this number' }) : null);
    const code = App.playCode(id, variant);
    const head = el('div', { class: 'hc-creature' },
      el('img', { src: App.iconFor(id, variant), width: o.small ? 24 : 36, height: o.small ? 24 : 36, alt: '' }),
      el('div', { class: 'hc-who' },
        el('div', { class: 'hc-name' }, el('b', { text: c.name }), code ? el('span', { class: 'hc-chip', text: code }) : null, at.arch !== 'regular' ? el('span', { class: 'hc-chip ' + at.arch, text: at.arch === 'boss' ? 'boss' : 'Elite' }) : null, o.share ? el('span', { class: 'hc-share', text: o.share }) : null),
        el('div', { class: 'hc-stats' }, dot(setHp), `HP ${fmtN(at.hp, 1)}`, ' · ', dot(setAtk), `ATK ${fmtN(at.atk, 1)}`, others.length ? el('span', { class: 'hc-star', text: ' *', title: 'other stats are overridden' }) : null)));
    const box = el('div', { class: 'hc-block' }, head);
    if (others.length && !o.small) box.appendChild(el('div', { class: 'hc-line others', text: `* also: ${others.slice(0, 8).join(', ')}${others.length > 8 ? ' …' : ''}` }));
    if (!o.small) {
      const parts = (ps) => ps.map(([k, v], n) => (n === 0 ? fmtN(v, 2) : `${k} ${fmtN(v, 2)}`)).join(' × ');
      box.appendChild(el('div', { class: 'hc-line muted', text: `HP ${parts(at.hpParts)}` }));
      box.appendChild(el('div', { class: 'hc-line muted', text: `ATK ${parts(at.atkParts)} · knock ${fmtN(App.knockbackOf(c, st), 2)} m/s` }));
      if (at.special) box.appendChild(el('div', { class: 'hc-line muted', text: `a coloured special (${Math.round(at.special.chance * 100)}% after colour_after_kills): HP ${fmtN(at.special.hp, 1)} · ATK ${fmtN(at.special.atk, 1)}` }));
    }
    return box;
  }

  function cardHead(title, t, sub) {
    return el('div', { class: 'hc-head' }, el('b', { text: title }), el('span', { class: 'hc-time', text: ` ${fmtT(t)} · ${App.stageName(App.stageAt(t))} · hero level ${App.S.level}` }), sub ? el('div', { class: 'hc-sub', text: sub }) : null);
  }

  function rosterCard(i, t) {
    const r = (App.tl().roster || [])[i];
    if (!r) return null;
    const open = App.rosterAt(t).find((o) => o.i === i);
    const share = open ? `${Math.round(open.norm * 100)}% of the ${r.channel === 'hell' ? 'hell channel\'s' : 'regular'} draw` : 'not drawn at this second';
    const box = el('div', {}, cardHead('Roster row', t, `${fmtT(r.t)} → ${r.until == null || r.until === '' ? 'end' : fmtT(r.until)}${r.id ? ` · ${r.id}` : ''}`));
    box.appendChild(creatureBlock(r.enemy, r.variant, r.stats, t));
    box.appendChild(el('div', { class: 'hc-line' }, el('b', { text: share }), open ? ` · weight ${fmtN(open.w, 2)}` : ''));
    return box;
  }

  function waveCard(i, t) {
    const wv = (App.tl().waves || [])[i];
    if (!wv) return null;
    const end = App.waveEnd(wv);
    const flags = [wv.respect_cap === false ? 'no cap' : '', wv.elite ? `elite ${wv.elite}` : '', wv.channel === 'hell' ? 'hell' : '', wv.toast ? `"${wv.toast}"` : ''].filter(Boolean).join(' · ');
    const box = el('div', {}, cardHead(waveHead(wv), t, `${fmtT(wv.t)} → ${end === Infinity ? 'no end' : fmtT(end)}${flags ? ' · ' + flags : ''}`));
    for (const a of App.waveAlts(wv).slice(0, 6)) box.appendChild(creatureBlock(a.alt.enemy, a.alt.variant, a.alt.stats, t, { small: true, share: `${Math.round(a.share * 100)}%` }));
    return box;
  }

  function altCard(i, k, t) {
    const wv = (App.tl().waves || [])[i];
    if (!wv) return null;
    const a = App.waveAlts(wv)[k];
    if (!a) return null;
    const box = el('div', {}, cardHead(a.alt.own ? 'Wave creature' : `Alternative ${k + 1}`, t, `${wv.name || wv.id || 'wave'} · ${Math.round(a.share * 100)}% of the roll${a.alt.pack != null ? ` · packs of ${a.alt.pack}` : ''}`));
    box.appendChild(creatureBlock(a.alt.enemy, a.alt.variant, a.alt.stats, t));
    return box;
  }

  function eventCard(i) {
    const ev = (App.tl().events || [])[i];
    if (!ev) return null;
    const t = Number(ev.t) || 0;
    const info = FIELDS.EVENT_TYPES[ev.type];
    const bits = [ev.chance != null && Number(ev.chance) < 1 ? `${Math.round(Number(ev.chance) * 100)}% chance` : '', ev.t_jitter ? `± ${ev.t_jitter} s` : '', ev.type === 'swarm' ? `${ev.count || 40} at once` : '', ev.mod ? `modifier ${ev.mod}` : ''].filter(Boolean).join(' · ');
    const box = el('div', {}, cardHead(App.eventLabel(ev), t, (info ? info.label : ev.type) + (bits ? ' · ' + bits : '')));
    const shares = App.eventShares(ev);
    if (shares.length) for (const s of shares.slice(0, 4)) box.appendChild(creatureBlock(s.id, ev.variant, ev.stats, t, { small: shares.length > 1, share: shares.length > 1 ? `${Math.round(s.share * 100)}%` : '' }));
    else if (ev.type === 'elite' || ev.type === 'elite_every') box.appendChild(el('div', { class: 'hc-line muted', text: 'a creature drawn from the roster rows open then, by their Elite weight, wearing a modifier' }));
    return box;
  }

  function specialsCard(t) {
    const sp = App.tl().specials || {};
    const box = el('div', {}, cardHead('Specials', t, `one at a time from ${fmtT(sp.from)}`));
    for (const row of (sp.pool || []).slice(0, 4)) {
      const id = typeof row === 'string' ? row : row.enemy;
      const st = typeof row === 'string' ? 1 : Number(row.stage || 1);
      box.appendChild(creatureBlock(id, '', null, t, { small: true, share: st > 1 ? `from stage ${st}` : '' }));
    }
    return box;
  }

  function shareCard(t) {
    const open = App.rosterAt(t);
    const box = el('div', {}, cardHead('Share of the draw', t));
    if (!open.length) { box.appendChild(el('div', { class: 'hc-line muted', text: 'no roster row open' })); return box; }
    for (const ch of [false, true]) {
      const by = {};
      for (const o of open.filter((x) => x.hell === ch)) by[o.row.enemy] = (by[o.row.enemy] || 0) + o.norm;
      const ids = Object.keys(by).sort((a, b) => by[b] - by[a]);
      if (!ids.length) continue;
      box.appendChild(el('div', { class: 'ro-title', text: ch ? 'hell channel' : 'regular crowd' }));
      const chart = el('div', { class: 'ro-chart' });
      for (const id of ids) {
        chart.appendChild(el('div', { class: 'ro-row' + (ch ? ' hell' : '') },
          el('img', { src: App.iconFor(id), width: 16, height: 16, alt: '' }),
          el('span', { class: 'ro-name', text: App.creatureName(id) }),
          el('span', { class: 'ro-bar' }, el('i', { style: `width:${Math.round(by[id] * 100)}%;background:${App.creatureColor(id)}` })),
          el('span', { class: 'ro-pct', text: `${Math.round(by[id] * 100)}%` })));
      }
      box.appendChild(chart);
    }
    return box;
  }

  // ------------------------------------------------------------------ cursor, readout, cards

  function onHover(e) {
    if (drag || !App.S.map) return;
    const t = tAt(e.clientX);
    if (t < 0 || e.clientX < svgLeft()) { hideCursor(); return; }
    cursorEl.hidden = false;
    cursorEl.style.left = `${LABEL_W + x(t)}px`;
    App.setClock(t);
    const target = e.target && e.target.closest ? e.target.closest('[data-hover]') : null;
    const key = target ? target.getAttribute('data-hover') : null;
    if (raf) cancelAnimationFrame(raf);
    raf = requestAnimationFrame(() => {
      raf = 0;
      if (drag) return;
      const build = key ? hovers[key] : null;
      const node = build ? build(Math.max(0, t)) : null;
      if (node) {
        readout.hidden = true;
        clear(card);
        card.appendChild(node);
        card.hidden = false;
        place(card, e.clientX, e.clientY);
      } else {
        hideCard();
        fillReadout(t, e.clientX, e.clientY);
      }
    });
  }

  function hideCursor() {
    cursorEl.hidden = true;
    readout.hidden = true;
    hideCard();
    App.setClock(null);
  }

  function fillReadout(t, cx, cy) {
    clear(readout);
    readout.hidden = false;
    const s = App.stageAt(t);
    const hp = App.hpMultAt(t), dm = App.dmgMultAt(t);
    const cap = App.capAt(t), hell = App.hellCapAt(t);
    readout.appendChild(el('div', { class: 'ro-head' }, el('b', { text: fmtT(t) }), ` · ${App.stageName(s)} · hero level ${App.S.level}`));
    readout.appendChild(el('div', { class: 'ro-line' }, `cap ${cap}`, hell > 0 ? ` + hell ${Math.floor(hell)}` : ''));
    const sp = lastSpawn ? Model.estimateAt(lastSpawn.est, t) : null;
    if (sp) readout.appendChild(el('div', { class: 'ro-line' }, `spawned so far ≈ ${fmtCount(sp.all)}`, el('small', { text: ` (estimate; ${fmtCount(sp.col)} coloured, ${fmtCount(sp.elite + sp.special + sp.boss)} Elites, specials and bosses)` })));
    readout.appendChild(el('div', { class: 'ro-line' }, `HP ×${fmtN(hp.total, 2)}`, el('small', { text: ` (time ${fmtN(hp.time, 2)} × stage ${fmtN(hp.stage, 2)} × level ${fmtN(hp.level, 2)} × creature ${fmtN(hp.creature, 2)})` })));
    readout.appendChild(el('div', { class: 'ro-line' }, `ATK ×${fmtN(dm.total, 2)}`, el('small', { text: ` (time ${fmtN(dm.time, 2)} × stage ${fmtN(dm.stage, 2)} × level ${fmtN(dm.level, 2)} × creature ${fmtN(dm.creature, 2)})` })));
    const rows = App.rosterAt(t);
    if (rows.length) {
      readout.appendChild(el('div', { class: 'ro-title', text: 'Roster drawn now' }));
      const chart = el('div', { class: 'ro-chart' });
      for (const o of rows.sort((a, b) => a.hell - b.hell || b.norm - a.norm)) {
        const c = App.creature(o.row.enemy);
        chart.appendChild(el('div', { class: 'ro-row' + (o.hell ? ' hell' : '') },
          c ? el('img', { src: App.iconFor(o.row.enemy, o.row.variant), width: 16, height: 16 }) : el('span', { class: 'ro-ico' }),
          el('span', { class: 'ro-name', text: App.creatureName(o.row.enemy) }),
          el('span', { class: 'ro-bar' }, el('i', { style: `width:${Math.round(o.norm * 100)}%;background:${App.creatureColor(o.row.enemy)}` })),
          el('span', { class: 'ro-pct', text: `${Math.round(o.norm * 100)}%` })));
      }
      readout.appendChild(chart);
    } else readout.appendChild(el('div', { class: 'ro-line muted', text: 'no roster row open' }));
    const ws = App.wavesAt(t);
    if (ws.length) {
      readout.appendChild(el('div', { class: 'ro-title', text: 'Waves running' }));
      for (const { w } of ws) readout.appendChild(el('div', { class: 'ro-line', text: `${w.name || w.id}: ${w.count || '∞'} in ${w.burst == null ? 5 : w.burst}s every ${w.every == null ? 2 : w.every} s${w.respect_cap === false ? ' (no cap)' : ''}` }));
    }
    const nx = App.nextEvent(t);
    if (nx) readout.appendChild(el('div', { class: 'ro-line' }, 'next: ', el('b', { text: App.eventLabel(nx.ev) }), ` at ${fmtT(nx.t)} (in ${fmtT(nx.t - t)})`));
    place(readout, cx, cy);
  }

  return { mount, render, fit, zoom, viewCenter, scrollToSelection, hideCard, LABEL_W, ALT_COLORS, get spp() { return spp; } };
})();
