// The Timeline tab (pass 53, pass 54): the calendar. A ruler with the stages, then one lane per part of the timeline (cap,
// HP x, ATK x, roster, share, waves, events, specials, paths), all on one time axis (x = seconds / spp), scrolling
// together, zoomable, with a cursor that follows the mouse and a readout of what the director would be doing at that
// second. Everything is drawn again from App.S on every change (a few thousand SVG nodes: cheap), so the drawing code
// never has to patch anything. Pass 54: a roster row's bar is a little graph of its presence keyframes (drag the points,
// double-click to add or remove one), the rows reorder from a gutter at the left, the Share band stacks each creature's
// share of the draw, and hovering a bar, a block, a stripe, a flag or the specials band shows a card with the creature's
// HP and ATK at that second. Pass 57: the "Spawned so far" lane under the cap (model.js spawnEstimate: every creature a run
// spawns by each second, with its hover card and the kill rate / boss fight / portal wait boxes in its label). Pass 58: a
// row's numbers are fixed from its start (the cards say so), the Actual HP x / ATK x lanes above the curves (model.js
// actualAt, on the curve's scale while the rows fit under it), a size range and a colour swatch on the bars, and a pressed
// bar is selected at once so its inspector follows the drag (Inspector.live; a box still being typed in commits first).
// Pass 61: snapping (the Snap toggle by the zoom, S, Alt for a free drag): a dragged start, end or point drops onto the
// cap's control points first, then the other rows' and waves' starts and ends, the events, the stage marks, whole and
// half minutes last (model.js snapDrag), with a guide line and the target named in the clock line while it is held.
'use strict';

const Timeline = (() => {
  const { el, svg, fmtT, fmtN, clear, glyph } = U;
  const LABEL_W = 170;
  const RULER_H = 60, CAP_H = 124, CURVE_H = 84, ROW_H = 36, ROSTER_HEAD = 40, EV_H = 92, SP_H = 42, PATH_H = 32, PAD = 6;
  const ALT_COLORS = ['#3987e5', '#d95926', '#199e70', '#c98500', '#d55181', '#9085e9', '#e66767', '#4cb5c3'];
  const HANDLE = 8;
  const CAP_HELP = 'The points are the control points of the live cap curve (how many creatures may be alive): linear between them, flat before the first and after the last. They are not spawn events: the director spawns up to the cap on its own interval.';
  // pass 58: the Actual HP x / ATK x lanes above their curves
  const ACT_HELP = {
    hp: 'The HP multiple the creatures really come with (pass 58): each roster row and wave keeps the HP curve of its own start (or its HP override) for its whole life. Solid: the average over what spawns round each second, weighted by how many each row spawns; dashed: the largest; dotted: the intended HP × curve. The HP × lane\'s scale while the rows fit under it; higher multiples give this lane its own (up to 1.5 times as tall) and a ▲ marks anything past the top. Hover for the rows behind the numbers; click for the curve.',
    dmg: 'The ATK multiple the creatures really come with (pass 58): each roster row and wave keeps the damage curve of its own start (or its damage override). Solid: the spawn-weighted average round each second; dashed: the largest; dotted: the intended ATK × curve. Hover for the rows behind the numbers.',
  };
  // pass 57: the "Spawned so far" lane under the cap
  const SPAWN_H = 132;
  // pass 83 (lane TIMELINE): what the window box and the readout's shares mean
  const WIN_HELP = 'The window (seconds) of the readout and the hover cards: hovering the timeline, each roster row and wave shows its share of all the creatures spawned in the past N seconds before the pointer (a wave\'s tick: in the N seconds from it). It is read off the Spawned so far estimate, which plays the director\'s rules second by second: the cap and its room, each row\'s weight, the spawn check and the rows\' own Draw every, the waves and what they owe, the kill rate. So a row paced as waves counts what its waves bring, and a row the cap starves counts little. Roster bars that spawned nothing in the window dim on the lane. 5 s by default; the browser remembers it.';
  const SPAWN_HELP = 'Every creature a run has spawned by each second, counted from 0:00: the regular crowd (blue), the coloured specials among it (orange), the elite-modified (purple) and the Elites, specials and bosses (gold, marked where they arrive). An estimate: a run only spawns what the hero kills, so it assumes the hero kills a share of the living crowd each second (from your own runs; the boxes change it) while the director refills to the cap under every rule of the timeline. Hover for the numbers.';
  let spp = 1.0;                       // seconds per pixel
  let root = null, scrollBox = null, content = null, cursorEl = null, readout = null, card = null, menu = null;
  const lanes = {};                    // name -> {row, label, svg}
  let drag = null;
  let raf = 0;
  let frozenMax = null;                // the roster's weight scale, held while a presence point is dragged
  // pass 61: snapping. On by default; the browser remembers the choice (a page setting, never written to the map).
  const SNAP_KEY = '88fits-editor-snap';
  // the guide line's colour per target kind: the cap curve's own blue, the roster's pink, the waves' green, an event its
  // flag's colour (FIELDS.EVENT_TYPES), the stage marks pale, the minutes grey
  const SNAP_COLORS = { cap: '#3987e5', row: '#e0609a', wave: '#2fbf8a', event: '#e6a04a', stage: '#c3c2b7', grid: '#a3a19a' };
  let snapOn = true;
  try { if (localStorage.getItem(SNAP_KEY) === '0') snapOn = false; } catch (_) { /* no storage: on */ }
  let snapEl = null;                   // the guide line (a div over the lanes) with its tag
  // pass 83 (lane TIMELINE; Garry: "let's make it so the highlight actually just shows the share of roster draw as the % of
  // enemies that spawned in the past 5 seconds (controllable value next to 'snap on')"): the readout's window in seconds,
  // a page setting the browser remembers (never written to the map)
  const WIN_KEY = '88fits-editor-window';
  const WIN_DEF = 5, WIN_MIN = 1, WIN_MAX = 120;
  let winSecs = WIN_DEF;
  try { const v = Number(localStorage.getItem(WIN_KEY)); if (v >= WIN_MIN && v <= WIN_MAX) winSecs = v; } catch (_) { /* no storage: 5 s */ }
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
      ['hp_act', 'Actual HP ×', null, '', ACT_HELP.hp],
      ['hp', 'HP ×', null, '', 'Creature health over the run clock (hp_curve): click to edit the curve, drag its points, double-click to add or remove one. Since pass 58 a row reads it once, at its start.'],
      ['dmg_act', 'Actual ATK ×', null, '', ACT_HELP.dmg],
      ['dmg', 'ATK ×', null, '', 'Creature damage over the run clock (damage_curve): click to edit, drag its points, double-click to add or remove one. Since pass 58 a row reads it once, at its start.'],
      ['roster', 'Roster', { text: '+ Row', title: 'Add a roster row at the view\'s centre', onclick: () => App.newRow(null, viewCenter()) }, '', ''],
      ['waves', 'Waves', { text: '+ Wave', title: 'Add a wave at the view\'s centre', onclick: () => App.newWave(null, viewCenter()) }, '', ''],
      ['events', 'Events', { text: '+ Event', title: 'Add an event at the view\'s centre', onclick: (e) => eventMenu(e.currentTarget) }, '', ''],
      ['specials', 'Specials', null, '', ''],
      ['paths', 'Mutations', null, '', 'When each stage\'s mutation offers fall due; each comes at the hero\'s next level-up (pass 79).'],
    ];
    for (const [name, title, plus, cls, help] of spec) {
      const head = name === 'roster' ? el('div', { class: 'lane-head' }, el('div', {}, el('div', { class: 'lane-name', text: title }), el('div', { class: 'lane-sub' }))) : null;
      const label = head
        ? el('div', { class: 'lane-label roster-label' }, head, el('div', { class: 'gutter' }))
        : el('div', { class: 'lane-label', title: help }, el('div', { class: 'lane-name', text: title }), el('div', { class: 'lane-sub' }));
      if (plus) (head || label).appendChild(el('button', { class: 'btn small plus', text: plus.text, title: plus.title, onclick: plus.onclick }));
      if (name === 'spawned') label.appendChild(spawnControls());
      const s = svg('svg', { class: 'lane-svg', height: 10 });
      const row = el('div', { class: 'lane lane-' + name + (cls ? ' ' + cls : '') }, label, s);
      label.addEventListener('click', (e) => {
        if (e.target.tagName === 'BUTTON' || e.target.closest('.gutter')) return;
        if (['cap', 'hp', 'dmg', 'specials', 'paths'].includes(name)) App.select({ kind: name });
        // an Actual lane opens its curve's inspector, which compares the two (pass 58)
        if (name === 'hp_act' || name === 'dmg_act') App.select({ kind: name === 'hp_act' ? 'hp' : 'dmg' });
      });
      content.appendChild(row);
      lanes[name] = { row, label, svg: s };
    }
    cursorEl = el('div', { class: 'tl-cursor', hidden: true });
    content.appendChild(cursorEl);
    snapEl = el('div', { class: 'tl-snap', hidden: true }, el('span', { class: 'tl-snap-tag' }));
    content.appendChild(snapEl);
    syncSnapButton();
    wireWindow();
    readout = el('div', { class: 'readout', hidden: true });
    document.body.appendChild(readout);
    card = el('div', { class: 'hovercard', hidden: true });
    document.body.appendChild(card);
    root.appendChild(scrollBox);
    scrollBox.addEventListener('pointermove', onHover);
    scrollBox.addEventListener('pointerleave', () => { if (!drag) hideCursor(); });
    scrollBox.addEventListener('scroll', () => { if (lastHover) lightRows(null); });
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
    // the estimate once a render: the Spawned so far lane and the Actual lanes' weights (pass 58)
    const res = App.spawned(!!drag);
    lastActual = App.actual(res);
    renderSpawned(w, res);
    renderActual(w, 'hp_act', true);
    renderCurve(w, 'hp', 'hp_curve');
    renderActual(w, 'dmg_act', false);
    renderCurve(w, 'dmg', 'damage_curve');
    renderRoster(w);
    renderWaves(w);
    renderEvents(w);
    renderSpecials(w);
    renderPaths(w);
    const selKey = App.selKey();
    for (const name of ['cap', 'hp', 'dmg', 'specials', 'paths']) lanes[name].row.classList.toggle('selected', selKey === name);
    lanes.hp_act.row.classList.toggle('selected', selKey === 'hp');
    lanes.dmg_act.row.classList.toggle('selected', selKey === 'dmg');
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
      // pass 54: every point carries its cap as a faint label (the time and the value in full on hover); pass 61: the
      // point a drag has snapped to is ringed
      const c = svg('g', { class: 'cap-point' + (snapIs('cap', k) ? ' snap-target' : ''), transform: `translate(${x(Number(p[0]) || 0)}, ${y(Number(p[1]) || 0)})` },
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
  function renderSpawned(w, given) {
    const s = clear(lanes.spawned.svg);
    setHeight('spawned', SPAWN_H);
    stageShade(s, SPAWN_H);
    syncSpawnControls();
    const res = given || App.spawned(!!drag);
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
    g.appendChild(svg('text', { x: 48, y: 11, class: 'sp-est', text: `estimate · kill rate from ${App.turnoverSource()}${shape}${res.stale ? ' · catching up with the drag' : ''}` }));
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

  // ------------------------------------------------------------------ Actual HP x and ATK x (pass 58)

  let lastActual = null;             // {series, est, stale}: what the Actual lanes drew last (their hover cards read it)

  /** The curve lane's y-scale: the curve over the view and its points, plus a margin. Its own (the review of pass 58: a
   *  scale shared with the Actual lane let one big HP override squash the curve Garry drags into the bottom of its lane). */
  function curveScale(isHp) {
    const d = App.tl();
    const key = isHp ? 'hp_curve' : 'damage_curve';
    const c = Model.hasCurve(d[key]) ? d[key] : null;
    const f = (t) => (isHp ? App.hpTimeMult(t) : App.dmgTimeMult(t));
    const end = App.viewEnd();
    let maxV = 1.5;
    for (let k = 0; k <= 120; k++) maxV = Math.max(maxV, f(end * k / 120));
    for (const p of (c && Array.isArray(c.points) ? c.points : [])) maxV = Math.max(maxV, Number(p[1]) || 0);
    return maxV * 1.15;
  }

  /** The Actual lane's y-scale (Garry: "so I would be able to compare how the intended HP multiple looks vs 'Actual'"):
   *  the curve lane's while the rows' multiples fit under it, so the two compare by eye; higher multiples lift it up to
   *  Model.ACTUAL_CLAMP times that (Model.actualScale), and anything above is drawn at the top with its number.
   *  {maxV, own, top: the rows' largest multiple}. */
  function actualScaleOf(isHp) {
    const own = curveScale(isHp);
    let top = 0;
    if (lastActual) for (const v of (isHp ? lastActual.series.hp.max : lastActual.series.atk.max)) if (v != null && isFinite(v)) top = Math.max(top, v);
    return { maxV: Model.actualScale(own, top), own, top };
  }

  /** An Actual lane: the intended curve dotted, the band from the average up to the largest, the largest dashed, the
   *  average solid; a gap where none of the roster or the waves spawns. A multiple past the lane's top is drawn at the top
   *  with a ▲ and its number. Hover for the rows behind the numbers. */
  function renderActual(w, name, isHp) {
    const s = clear(lanes[name].svg);
    setHeight(name, CURVE_H);
    stageShade(s, CURVE_H);
    const sc = actualScaleOf(isHp);
    const maxV = sc.maxV;
    // the lines keep below the legend along the lane's top
    const top = 16, bottom = CURVE_H - 10;
    const y = (v) => bottom - (Math.min(Math.max(0, v), maxV) / maxV) * (bottom - top);
    const gstep = [0.25, 0.5, 1, 2, 5, 10, 20, 50].find((g) => maxV / g <= 4) || 100;
    for (let v = gstep; v < maxV; v += gstep) {
      s.appendChild(svg('line', { x1: 0, x2: w, y1: y(v), y2: y(v), class: 'grid' + (Math.abs(v - 1) < 1e-9 ? ' one' : '') }));
      s.appendChild(svg('text', { x: 4, y: y(v) - 2, class: 'grid-text', text: `×${fmtN(v, 2)}` }));
    }
    const kind = isHp ? 'hp' : 'dmg';
    const g = svg('g', { class: 'actual ' + kind, 'data-hover': name });
    g.appendChild(svg('rect', { x: 0, y: 0, width: w, height: CURVE_H, class: 'sp-hit' }));
    const f = (t) => (isHp ? App.hpTimeMult(t) : App.dmgTimeMult(t));
    const end = App.viewEnd();
    let line = '';
    for (let px = 0; px <= x(end); px += 3) line += `${px},${y(f(px * spp))} `;
    g.appendChild(svg('polyline', { points: line, class: 'act-intended ' + kind }));
    const ser = lastActual ? lastActual.series : null;
    let spans = 0, clipped = 0;
    if (ser) {
      const avg = isHp ? ser.hp.avg : ser.atk.avg, mx = isHp ? ser.hp.max : ser.atk.max;
      // runs of seconds where something spawns
      let run = [];
      const flush = () => {
        if (!run.length) return;
        spans++;
        const up = run.map((i) => `${x(ser.ts[i])},${y(mx[i])}`);
        const down = run.map((i) => `${x(ser.ts[i])},${y(avg[i])}`);
        g.appendChild(svg('polygon', { points: up.concat(down.slice().reverse()).join(' '), class: 'act-band ' + kind }));
        g.appendChild(svg('polyline', { points: up.join(' '), class: 'act-max ' + kind }));
        g.appendChild(svg('polyline', { points: down.join(' '), class: 'act-avg ' + kind }));
        // past the top: a ▲ and the number at the run's highest second
        let peak = run[0];
        for (const i of run) if (mx[i] > mx[peak]) peak = i;
        if (mx[peak] > maxV + 1e-9) {
          clipped++;
          const px = Math.min(Math.max(x(ser.ts[peak]), 4), w - 60);
          // just under the lane's top, haloed over the band
          g.appendChild(svg('text', { x: px, y: top + 13, class: 'act-clip ' + kind, text: `▲ ×${fmtN(mx[peak], 2)}` }));
        }
        run = [];
      };
      for (let i = 0; i < ser.ts.length; i++) {
        if (avg[i] == null || mx[i] == null) flush(); else run.push(i);
      }
      flush();
    }
    const what = isHp ? 'HP' : 'ATK';
    const scaleNote = sc.maxV > sc.own + 1e-9 ? ` · its own scale, up to ×${fmtN(sc.maxV, 2)} (the ${what} × lane's top is ×${fmtN(sc.own, 2)})` : '';
    const clipNote = clipped ? ' · ▲ past the top, with its number' : '';
    g.appendChild(svg('text', { x: 48, y: 11, class: 'sp-est', text: `solid: the average · dashed: the largest · dotted: the intended ${what} × below${scaleNote}${clipNote}${lastActual && lastActual.stale ? ' · catching up with the drag' : ''}` }));
    hovers[name] = (t) => actualCard(t, isHp);
    s.appendChild(g);
    lanes[name].label.querySelector('.lane-sub').textContent = spans ? 'each row fixed from its start' : 'nothing spawns from the roster or the waves';
  }

  /** "×1.62" for a multiple, "–" for none. */
  const fmtX = (v) => (v == null ? '–' : `×${fmtN(v, 2)}`);

  /** The Actual lane's card: the average, the largest and the intended at that second, then every row and wave spawning
   *  round it (the estimate's window) with its start, its multiple, why (the curve at its start, or its override) and its
   *  share of those spawns. */
  function actualCard(t, isHp) {
    if (!lastActual) return null;
    const a = App.actualAt(t, lastActual.est);
    const what = isHp ? 'HP' : 'ATK';
    const intended = isHp ? App.hpTimeMult(t) : App.dmgTimeMult(t);
    const agg = isHp ? a.hp : a.atk;
    const box = el('div', { class: 'act-card' });
    box.appendChild(el('div', { class: 'hc-head' }, el('b', { text: `Actual ${what} ×` }), el('span', { class: 'hc-time', text: ` ${fmtT(t)} · ${App.stageName(App.stageAt(t))}${lastActual.stale ? ' · catching up with the drag' : ''}` })));
    box.appendChild(el('div', { class: 'act-big' },
      el('span', {}, 'average ', el('b', { text: fmtX(agg.avg) })), el('span', {}, 'largest ', el('b', { text: fmtX(agg.max) })),
      el('span', { class: 'muted' }, 'intended ', el('b', { text: fmtX(intended) }))));
    if (!a.rows.length) {
      box.appendChild(el('div', { class: 'hc-line muted', text: `Nothing of the roster or the waves spawns round this second. Swarms, coloured elites and the specials are not counted in this lane: each takes the curves at the second it comes, or the numbers of a row or wave bringing the same creature then. Elite mini-bosses and bosses keep their own rules.` }));
      return box;
    }
    box.appendChild(el('div', { class: 'hc-line muted', text: `What spawns from ${fmtT(Math.max(0, t - a.win / 2))} to ${fmtT(t + a.win / 2)} (the Spawned so far estimate), each row's numbers fixed from its start:` }));
    const grid = el('div', { class: 'act-grid' });
    const tl = App.tl();
    for (const r of a.rows.slice(0, 12)) {
      const m = isHp ? r.hp : r.atk;
      const over = isHp ? r.hpOver : r.dmgOver;
      const src = r.kind === 'roster' ? ((tl.roster || [])[r.i] || {}) : ((tl.waves || [])[r.i] || {});
      const who = r.kind === 'roster' ? `row ${src.id || r.i + 1}` : `${src.name || src.id || 'wave'}${Array.isArray(src.alts) && src.alts.length > 1 ? ` · alt ${r.k + 1}` : ''}`;
      const why = r.arch !== 'regular' ? (isHp ? 'an Elite / boss: no curve' : `live curve ${fmtX(App.dmgTimeMult(t))}`)
        : over ? `its own ${isHp ? 'HP' : 'damage'} (no curve)` : `the curve at ${fmtT(r.t0)}`;
      grid.appendChild(el('div', { class: 'act-r' + (r.hell ? ' hell' : '') },
        el('img', { src: App.iconFor(r.id, r.variant), alt: '' }),
        // in endless a row is fixed afresh at each wave (lane WV's fix round): its own start, then the wave's
        el('span', { class: 'nm' }, App.creatureName(r.id), el('small', { text: ` ${who} · from ${fmtT(r.start == null ? r.t0 : r.start)}${r.start != null && r.t0 > r.start + 1e-9 ? `, afresh at ${fmtT(r.t0)}` : ''}` })),
        el('b', { class: 'mx' + (agg.max != null && m != null && Math.abs(m - agg.max) < 1e-9 && a.rows.length > 1 ? ' top' : ''), text: fmtX(m) }),
        el('span', { class: 'why', text: why }),
        el('span', { class: 'pc', text: `${Math.round(r.share * 100)}%` })));
    }
    box.appendChild(grid);
    if (a.rows.length > 12) box.appendChild(el('div', { class: 'hc-line muted', text: `… and ${a.rows.length - 12} more` }));
    box.appendChild(el('div', { class: 'hc-line muted', text: `In the game the stage multiplier, creature_${isHp ? 'hp' : 'damage'}_mult and the hero level come on top of these. Swarms, coloured elites and the specials are not counted here: each takes the curves at the second it comes, or the numbers of a row or wave bringing the same creature then.` }));
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
    // its own scale (the Actual lane above shares it while the rows' multiples fit under it, pass 58)
    const maxV = curveScale(isHp);
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
      const g = svg('g', { class: 'bar' + (r.channel === 'hell' ? ' hell' : '') + (App.selKey() === key ? ' selected' : '') + (snapIs('roster', i) ? ' snap-target' : '') + issueClass(key), 'data-key': key, 'data-hover': key });
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
      // pass 58: a size range and a swatch of the colour range
      const sr = Model.sizeRange(r.stats && r.stats.size);
      if (sr && sr.range) chips.push(sr.min === sr.max ? { text: `${fmtN(sr.min, 2)} m`, cls: 'chip-size', title: 'every creature of the row this size (a list of one size: no spread)' } : { text: `${fmtN(sr.min, 2)}–${fmtN(sr.max, 2)} m`, cls: 'chip-size', title: 'each creature of the row its own size in this range' });
      const tr = Model.tintRange(r.stats && r.stats.tint);
      if (tr) chips.push({ hue: tr, cls: 'chip-hue', title: `coloured ${Math.round(tr.h0)}°–${Math.round(tr.h1)}° at ${Math.round(tr.amount * 100)}%` });
      if (r.stats && Object.keys(r.stats).length) chips.push({ glyph: 'wrench', cls: 'chip-wrench' });
      // pass 81 (lane PACE): a row paced as waves says how often and how many
      if (Model.rowPaced(r)) chips.push(paceChip(r, c));
      for (const ch of chips) tx = chip(inner, tx, y0 + 2, ch);
      // pass 81 (lane PACE): the yellow etches along the bar's foot, when its creatures come
      rowEtches(inner, r, t, tEnd, y0 + bh);
      g.appendChild(inner);
      // pass 83 (lane TIMELINE): the foot of the bar, where the ticks are, hovers as the tick nearest the pointer
      g.appendChild(svg('rect', { x: x0, y: y0 + bh - 11, width: Math.max(0, x1 - x0 - HANDLE), height: 11, class: 'etch-hit', 'data-hover': `etch:${i}` }));
      hovers[`etch:${i}`] = (tt) => etchCard(i, tt);
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

  /** The yellow etches (pass 81, lane PACE; Garry: "on top of the enemy node in the rows you should etch the yellow etches
   *  to show when the enemies will spawn. If it's continuous ... it's shown as a continuous yellow line") along a bar's
   *  foot `yf`, from `t0` to `t1`: a yellow line where a continuous row (or a waves row that also trickles, thinner) is
   *  drawn, its weight above 0; a tick at each wave of a row paced as waves that comes (its weight above 0 then). Ticks
   *  closer than ETCH_MIN_PX on the screen are thinned, every m-th kept, never merged into a line. They follow the zoom
   *  (x(t)) and every change of the row (the whole lane is drawn again). */
  function rowEtches(parent, r, t0, t1, yf) {
    const lateT = App.tl().weight_late_t;
    const paced = Model.rowPaced(r);
    const g = svg('g', { class: 'etches' + (paced ? ' paced' : '') });
    if (Model.rowDrawn(r)) {
      // pass 83 (lane TIMELINE; Garry: "since continuous spawning has these inevitable intervals the notches on the enemy
      // node should reflect that"): a short tick at each draw (the spawn check's rhythm, or the row's own Draw every)
      // where its weight is above 0; a dotted line where the ticks would be under ETCH_MIN_PX apart (never solid)
      const si = spawnCheck();
      const dense = Model.rowDrawInterval(r, si) < Model.ETCH_MIN_PX * spp;
      for (const [a, b] of Model.presenceSpans(r, t0, t1, lateT)) {
        if (dense) { g.appendChild(svg('line', { x1: x(a), x2: x(b), y1: yf - 2.5, y2: yf - 2.5, class: 'etch-dots' + (paced ? ' trickle' : '') })); continue; }
        let d = '';
        for (const tk of Model.rowDrawTimes(r, a, b, si, lateT)) d += `M${x(tk).toFixed(1)},${yf}v-${paced ? 4 : 6}`;
        if (d) g.appendChild(svg('path', { d, class: 'etch-draw' + (paced ? ' trickle' : '') }));
      }
    }
    if (paced) {
      const thin = Model.thinTimes(Model.rowEtchTimes(r, t1, lateT), Model.ETCH_MIN_PX * spp);
      for (const tk of thin.times) g.appendChild(svg('line', { x1: x(tk), x2: x(tk), y1: yf - 1, y2: yf - 11, class: 'etch-tick' }));
    }
    parent.appendChild(g);
  }

  /** Ticks along a waves[] block's foot at its bursts (pass 81), thinned like the rows'. */
  function waveEtches(parent, wv, tEnd, yf) {
    const thin = Model.thinTimes(Model.waveBurstTimes(wv, tEnd), Model.ETCH_MIN_PX * spp);
    const g = svg('g', { class: 'etches paced' });
    for (const tk of thin.times) g.appendChild(svg('line', { x1: x(tk), x2: x(tk), y1: yf - 1, y2: yf - 9, class: 'etch-tick' }));
    parent.appendChild(g);
  }

  /** A waves row's chip (pass 81): "↻ 30 s ×20" (every how often, how many a wave), "once ×20" for every 0. */
  function paceChip(r, c) {
    const every = Model.rowWaveEvery(r), n = Model.rowWaveCount(r, c);
    return { text: every > 0 ? `↻ ${fmtN(every, 1)} s ×${n}` : `once ×${n}`, cls: 'chip-pace', title: `paced as waves: ${n} every ${every > 0 ? `${fmtN(every, 2)} s` : 'once'} from ${fmtT(Model.rowWaveStart(r))}${r.respect_cap === false ? ', on top of the cap' : ''}${r.trickle ? ', also continuous' : ''}` };
  }

  /** The wave of row `r` that comes next at or after `t` (pass 81), null when none does before its end or the view's. */
  function nextRowWave(r, t) {
    const end = r.until == null || r.until === '' ? App.viewEnd() : Number(r.until);
    const ts = Model.rowEtchTimes(r, end, App.tl().weight_late_t);
    for (const tk of ts) if (tk >= t) return tk;
    return null;
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

  let gradSeq = 0;
  function chip(parent, tx, ty, ch) {
    const w = ch.glyph ? 20 : ch.hue ? 30 : textWidth(ch.text, 10) + 10;
    const g = svg('g', { class: 'chip ' + (ch.cls || '') });
    if (ch.title) g.appendChild(svg('title', {}, ch.title));
    if (ch.hue) {
      // a swatch of the colour range (pass 58): the hues from → to, wrapping through red when the range does
      const id = `hue-grad-${++gradSeq}`;
      const grad = svg('linearGradient', { id, x1: 0, x2: 1, y1: 0, y2: 0 });
      for (const [off, rgb] of U.hueStops(ch.hue.h0, ch.hue.h1, ch.hue.sat, ch.hue.val, 7)) grad.appendChild(svg('stop', { offset: off, 'stop-color': rgb }));
      g.appendChild(grad);
      // an inline fill: the chips' own `.chip rect` fill in style.css would win over the attribute
      g.appendChild(svg('rect', { x: tx, y: ty, width: w, height: 15, rx: 7, style: `fill:url(#${id})`, class: 'hue-rect' }));
      parent.appendChild(g);
      return tx + w + 5;
    }
    g.appendChild(svg('rect', { x: tx, y: ty, width: w, height: 15, rx: 7 }));
    if (ch.glyph) g.appendChild(svg('use', { href: '#g-' + ch.glyph, x: tx + 3, y: ty + 0.5, width: 14, height: 14 }));
    else g.appendChild(svg('text', { x: tx + 5, y: ty + 11, class: 'chip-text', text: ch.text }));
    parent.appendChild(g);
    return tx + w + 5;
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
      const g = svg('g', { class: 'block' + (App.selKey() === key ? ' selected' : '') + (wv.respect_cap === false ? ' nocap' : '') + (wv.channel === 'hell' ? ' hell' : '') + (snapIs('wave', b.i) ? ' snap-target' : '') + issueClass(key), 'data-key': key, 'data-hover': key });
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
      // pass 81 (lane PACE): a tick at each burst along the block's foot
      waveEtches(inner, wv, Math.min(b.e, end), y0 + b.h);
      g.appendChild(inner);
      // pass 83 (lane TIMELINE): hovering the ticks names the burst nearest the pointer
      g.appendChild(svg('rect', { x: b.x0, y: y0 + b.h - 10, width: Math.max(0, b.x1 - b.x0 - HANDLE), height: 10, class: 'etch-hit', 'data-hover': `wetch:${b.i}` }));
      hovers[`wetch:${b.i}`] = (tt) => burstCard(b.i, tt);
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
      // pass 58: a size range reads "size 1.2–1.6", a colour range "colour 200–260°"
      if (k === 'size' && Array.isArray(v)) parts.push(`size ${v.join('–')}`);
      else if (k === 'tint' && U.isObj(v)) { const tr = Model.tintRange(v); parts.push(tr ? `colour ${Math.round(tr.h0)}–${Math.round(tr.h1)}°` : 'colour'); }
      else if (typeof v === 'object') parts.push(k);
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
      const g = svg('g', { class: 'marker' + (App.selKey() === key ? ' selected' : '') + (faded ? ' faded' : '') + (snapIs('event', e.i) ? ' snap-target' : '') + issueClass(key), 'data-key': key, 'data-hover': key });
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
      g.appendChild(svg('use', { href: '#g-' + info.glyph, x: px - 8, y: cy - 8, width: 16, height: 16, fill: e.ev.special ? specialColour(e.ev) : info.color }));
      g.appendChild(svg('text', { x: px + 13, y: cy + 4, class: 'marker-text', text: label + (e.ev.special ? '  ★' : '') + (faded ? `  ${Math.round(Number(e.ev.chance) * 100)}%` : '') }));
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

  /** Pass 69 (lane EN): a swarm set to Special is drawn in its creature's special colour at full brightness (the glow's
   *  colour), pink when it has none. */
  function specialColour(ev) {
    const c = App.creature(U.idList(ev.enemy)[0]);
    const hex = c && U.isObj(c.variance) && U.isObj(c.variance.special) ? String(c.variance.special.tint || '') : '';
    const m = hex.match(/^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i);
    if (!m) return '#e0609a';
    const rgb = [1, 2, 3].map((k) => parseInt(m[k], 16));
    const mx = Math.max(rgb[0], rgb[1], rgb[2], 1);
    return '#' + rgb.map((v) => Math.round(v * 255 / mx).toString(16).padStart(2, '0')).join('');
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
    if (!pt.length) g.appendChild(svg('text', { x: 8, y: 20, class: 'hint-text', text: 'no mutation offers (Settings → Items)' }));
    const bd = issueBadge(key, 10, 10);
    if (bd) g.appendChild(bd);
    s.appendChild(g);
    lanes.paths.label.querySelector('.lane-sub').textContent = plural(n, 'offer');
  }

  // ------------------------------------------------------------------ drag

  /** A box still being typed in (the inspector's, the Hero level, a Spawned so far box) commits before a drag starts
   *  (the review of pass 58): its blur fires 'change', its own undo step, and the drag starts from the map with that edit
   *  in it. Left focused, the select-on-press below cleared the inspector round it, the box committed from inside that
   *  clear, its apply drew the inspector again, and the clear threw NotFoundError half way: the drag never started and the
   *  hover cards stayed dead. (The pointerdown's preventDefault keeps the focus where it was, so nothing else blurs it.) */
  function commitPending() {
    const ae = document.activeElement;
    if (!ae || ae === document.body || typeof ae.blur !== 'function') return;
    if (/^(INPUT|SELECT|TEXTAREA)$/.test(ae.tagName) || ae.isContentEditable) ae.blur();
  }

  function startDrag(e, spec) {
    if (e.button !== 0) return;
    e.stopPropagation();
    e.preventDefault();
    hideCard();
    commitPending();
    const tl = App.tl();
    const item = spec.kind === 'roster' || spec.kind === 'weight' ? tl.roster[spec.i] : spec.kind === 'wave' ? tl.waves[spec.i] : spec.kind === 'event' ? tl.events[spec.i] : null;
    const pair = (p) => [Number(p[0]) || 0, Number(p[1]) || 0];
    // pass 61: what this drag can snap to, from the timeline as it is before the drag (the dragged item's own start and
    // end, or the dragged cap point, left out: it never snaps to itself)
    const self = spec.kind === 'cap' ? { kind: 'cap', k: spec.k } : spec.kind === 'roster' || spec.kind === 'wave' || spec.kind === 'event' ? { kind: spec.kind, i: spec.i } : null;
    drag = {
      spec, x0: e.clientX, y0: e.clientY, moved: false, before: App.snapshot(),
      t0: item ? Number(item.t) || 0 : 0,
      until0: item && item.until != null && item.until !== '' ? Number(item.until) : null,
      end0: item && spec.kind === 'wave' ? App.waveEnd(item) : null,
      p0: spec.kind === 'cap' ? pair(tl.cap_curve[spec.k]) : spec.kind === 'curve' ? pair(tl[spec.key].points[spec.k]) : spec.kind === 'weight' ? pair(item.weights[spec.k]) : null,
      w0: spec.kind === 'roster' && item && Array.isArray(item.weights) ? item.weights.map(pair) : null,
      targets: Model.snapTargets(tl, self), snap: null, last: null,
    };
    if (spec.kind === 'weight') frozenMax = spec.maxW;
    // the drag's own listeners first, so nothing below can leave `drag` set with no pointerup to end it (the hover cards
    // wait while it is set)
    document.body.classList.add('dragging');
    window.addEventListener('pointermove', onDragMove);
    window.addEventListener('pointerup', onDragUp, { once: true });
    window.addEventListener('keydown', onDragKey);
    window.addEventListener('keyup', onDragKey);
    // pass 58: a bar, block or flag pressed is selected at once, so its inspector shows the row's fixed HP and ATK
    // changing while it is dragged (Garry: "as I move the enemy bar left and right the actual HP value in the stats
    // changes")
    if ((spec.kind === 'roster' || spec.kind === 'wave' || spec.kind === 'event') && App.selKey() !== `${spec.kind}:${spec.i}`) {
      App.S.sel = { kind: spec.kind, i: spec.i };
      try { Inspector.render(document.getElementById('inspector')); } catch (err) { console.error('the inspector could not be drawn for the drag', err); }
    }
  }

  function onDragMove(e) {
    if (!drag) return;
    drag.last = { clientX: e.clientX, clientY: e.clientY, altKey: !!e.altKey };
    const dx = e.clientX - drag.x0;
    if (!drag.moved && Math.abs(dx) < 3 && Math.abs(e.clientY - drag.y0) < 3) return;
    drag.moved = true;
    const dt = Math.round(dx * spp);
    const tl = App.tl();
    const sp = drag.spec;
    // pass 61: the snap for this move (null with Snap off, Alt held or nothing within SNAP_PX); set before the render so
    // the lanes can ring the target
    const snapOpts = { spp, on: snapOn, alt: !!e.altKey, targets: drag.targets };
    const snapTo = (edges) => { drag.snap = Model.snapDrag(tl, edges, snapOpts); return drag.snap; };
    if (sp.kind === 'cap' || sp.kind === 'curve') {
      const p = sp.kind === 'cap' ? tl.cap_curve[sp.k] : tl[sp.key].points[sp.k];
      const raw = Math.max(0, drag.p0[0] + dt);
      const sn = snapTo([{ t: raw, edge: 'point', min: 0 }]);
      p[0] = sn ? sn.t : raw;
      const dv = -((e.clientY - drag.y0) / (sp.bottom - sp.top)) * sp.maxV;
      p[1] = sp.kind === 'cap' ? Math.max(0, Math.round(drag.p0[1] + dv)) : Math.max(0, Model.round(drag.p0[1] + dv, 2));
      render();
      showSnap(sn, e);
      App.setClock(p[0], (sp.kind === 'cap' ? `cap ${p[1]}` : `×${p[1]}`) + snapText(sn));
      return;
    }
    if (sp.kind === 'weight') {
      const p = tl.roster[sp.i].weights[sp.k];
      const raw = Math.max(0, drag.p0[0] + dt);
      const sn = snapTo([{ t: raw, edge: 'point', min: 0 }]);
      p[0] = sn ? sn.t : raw;
      const dw = -((e.clientY - drag.y0) / sp.span) * sp.maxW;
      p[1] = Math.max(0, Model.round(drag.p0[1] + dw, 1));
      render();
      showSnap(sn, e);
      // the row's Presence boxes follow the point (when the inspector shows that row)
      Inspector.live();
      App.setClock(p[0], `weight ${p[1]}` + snapText(sn));
      return;
    }
    const item = sp.kind === 'roster' ? tl.roster[sp.i] : sp.kind === 'wave' ? tl.waves[sp.i] : tl.events[sp.i];
    if (!item) return;
    let sn = null;
    if (sp.mode === 'move') {
      // the whole bar moves: its start and its end (a row's until, a wave's until or the end its count gives) both look
      // for a target, and the better one moves the bar
      const raw = Math.max(0, drag.t0 + dt);
      const len = drag.until0 != null ? drag.until0 - drag.t0 : drag.end0 != null && drag.end0 !== Infinity ? Math.round(drag.end0 - drag.t0) : null;
      const edges = [{ t: raw, edge: 'start', min: 0 }];
      if (len != null && len > 0) edges.push({ t: raw + len, edge: 'end', min: len });
      sn = snapTo(edges);
      const nt = sn ? Math.max(0, raw + sn.delta) : raw;
      item.t = nt;
      if (drag.until0 != null) item.until = Math.max(nt + 1, drag.until0 + (nt - drag.t0));
      // a roster row's presence keyframes are run-clock times: they travel with the bar
      if (sp.kind === 'roster' && drag.w0) item.weights = drag.w0.map(([pt, pv]) => [Math.max(0, pt + (nt - drag.t0)), pv]);
    } else {
      const base = drag.until0 != null ? drag.until0 : (drag.end0 != null && drag.end0 !== Infinity ? Math.round(drag.end0) : Math.round(tAt(drag.x0)));
      const lo = (Number(item.t) || 0) + 1;
      const raw = Math.max(lo, Math.round(base + dt));
      sn = snapTo([{ t: raw, edge: 'end', min: lo }]);
      item.until = sn ? sn.t : raw;
    }
    render();
    showSnap(sn, e);
    Inspector.live();
    // a bar moved by its end says so: the clock shows its start
    App.setClock(sp.mode === 'until' ? Number(item.until) : Number(item.t), (sp.mode === 'until' ? 'until' : 'from') + (sn && sp.mode === 'move' && sn.edge === 'end' ? ` · its end snapped to ${sn.target.label}` : snapText(sn)));
  }

  /** Alt pressed or let go mid-drag frees or snaps the drag where the mouse stands (pass 61); the key's own default
   *  (the browser's menu on Windows) is held back while a drag runs. */
  function onDragKey(e) {
    if (!drag || e.key !== 'Alt') return;
    e.preventDefault();
    if (drag.moved && drag.last) onDragMove({ clientX: drag.last.clientX, clientY: drag.last.clientY, altKey: e.type === 'keydown' });
  }

  function onDragUp() {
    window.removeEventListener('pointermove', onDragMove);
    window.removeEventListener('keydown', onDragKey);
    window.removeEventListener('keyup', onDragKey);
    document.body.classList.remove('dragging');
    showSnap(null);
    if (!drag) return;
    const d = drag; drag = null;
    frozenMax = null;
    // an Alt still held as the button comes up: its keyup must not open the browser's menu either
    if (d.last && d.last.altKey) window.addEventListener('keyup', (ev) => { if (ev.key === 'Alt') ev.preventDefault(); }, { once: true });
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

  // ------------------------------------------------------------------ snapping (pass 61)

  /** True when the drag's snap target is that item: a cap point k, or a roster row / wave / event i (it is ringed). */
  function snapIs(kind, n) {
    const r = drag && drag.snap ? drag.snap.target.ref : null;
    return !!r && r.kind === kind && (kind === 'cap' ? r.k === n : r.i === n);
  }

  /** The target kind's colour (an event its flag's). */
  function snapColor(target) {
    if (target.kind === 'event') {
      const ev = (App.tl().events || [])[target.ref.i];
      const info = ev ? FIELDS.EVENT_TYPES[ev.type] : null;
      return info ? info.color : SNAP_COLORS.event;
    }
    return SNAP_COLORS[target.kind] || SNAP_COLORS.grid;
  }

  const snapText = (sn) => (sn ? ` · snapped to ${sn.target.label}` : '');

  /** The guide line across the lanes at the snapped time, in the target's colour, its tag just above the mouse; hidden
   *  with no snap. */
  function showSnap(sn, e) {
    if (!snapEl) return;
    if (!sn) { snapEl.hidden = true; return; }
    const col = snapColor(sn.target);
    snapEl.hidden = false;
    snapEl.style.left = `${LABEL_W + x(sn.t)}px`;
    snapEl.style.borderLeftColor = col;
    const tag = snapEl.firstChild;
    tag.textContent = `snapped to ${sn.target.label}`;
    tag.style.background = col;
    const yIn = e ? e.clientY - content.getBoundingClientRect().top - 34 : RULER_H + 6;
    tag.style.top = `${Math.max(scrollBox.scrollTop + RULER_H + 4, yIn)}px`;
  }

  function syncSnapButton() {
    const b = document.getElementById('snap-toggle');
    if (!b) return;
    b.classList.toggle('on', snapOn);
    b.setAttribute('aria-pressed', String(snapOn));
    b.textContent = snapOn ? 'Snap on' : 'Snap off';
  }

  /** The Snap toggle (the button by the zoom, or S): remembered by the browser; a drag under way follows it at once. */
  function setSnap(on) {
    snapOn = !!on;
    try { localStorage.setItem(SNAP_KEY, snapOn ? '1' : '0'); } catch (_) { /* fine */ }
    syncSnapButton();
    if (drag && drag.moved && drag.last) onDragMove(drag.last);
  }
  function toggleSnap() { setSnap(!snapOn); return snapOn; }

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
  /** A row's size and colour ranges for a card (pass 58): "size 1.2–1.6 m, each its own" and a strip of the hue range
   *  with "200°–260° at 50%". Null when the row sets neither. */
  function rangeLine(st, c) {
    const sr = Model.sizeRange(st.size);
    const tr = Model.tintRange(st.tint);
    if (!sr && !tr) return null;
    const line = el('div', { class: 'hc-line ranges' });
    if (sr) line.appendChild(el('span', { text: sr.range ? (sr.min === sr.max ? `size ${fmtN(sr.min, 2)} m, all alike (no spread)` : `size ${fmtN(sr.min, 2)}–${fmtN(sr.max, 2)} m, each its own`) + (c ? ` (its own ${fmtN(Number(c.size), 2)} m)` : '') : `size ${fmtN(sr.min, 2)} m` }));
    if (sr && tr) line.appendChild(document.createTextNode(' · '));
    if (tr) {
      line.appendChild(el('span', { class: 'hue-strip', style: `background:${U.hueGradient(tr.h0, tr.h1, tr.sat, tr.val)}` }));
      line.appendChild(el('span', { text: ` ${Math.round(tr.h0)}°–${Math.round(tr.h1)}° at ${Math.round(tr.amount * 100)}%` }));
    }
    return line;
  }

  function creatureBlock(id, variant, stats, t, opts) {
    const o = opts || {};
    const c = App.creature(id);
    if (!c) return el('div', { class: 'hc-line bad', text: `unknown creature "${id || ''}"` });
    const st = U.isObj(stats) ? stats : {};
    // pass 58 (R1): a row's numbers are fixed from its start (o.t0); the stage at t and the hero level come on top. An
    // event (o.event) plays a row's numbers while that row brings the same creature in the same look (lane WV's fix round)
    const given = o.event && o.t0 != null ? App.eventNumbers(id, variant, st, o.t0) : null;
    const at = App.creatureAt(c, st, t, o.t0, given && given.joined ? given : null);
    const setHp = st.hp != null || st.hp_mult != null || (at.arch === 'elite' && U.getPath(st, 'elite.hp_mult_per_stage') != null) || (at.arch === 'boss' && U.getPath(st, 'boss.hp_mult_per_stage') != null);
    const setAtk = st.damage != null || st.damage_mult != null;
    const others = Model.otherOverrides(st).filter((s) => !(at.arch === 'elite' && s.startsWith('elite.hp_mult_per_stage')) && !(at.arch === 'boss' && s.startsWith('boss.hp_mult_per_stage'))
      && !/^size\b/.test(s) && !/^tint\b/.test(s));
    const dot = (on) => (on ? el('span', { class: 'hc-dot', title: 'an override changes this number' }) : null);
    const code = App.playCode(id, variant);
    const head = el('div', { class: 'hc-creature' },
      el('img', { src: App.iconFor(id, variant), width: o.small ? 24 : 36, height: o.small ? 24 : 36, alt: '' }),
      el('div', { class: 'hc-who' },
        el('div', { class: 'hc-name' }, el('b', { text: c.name }), code ? el('span', { class: 'hc-chip', text: variant ? code : `${code} · default`, title: variant ? 'this row\'s own look' : 'the creature\'s default look (the Creatures tab sets it)' }) : null, at.arch !== 'regular' ? el('span', { class: 'hc-chip ' + at.arch, text: at.arch === 'boss' ? 'boss' : 'Elite' }) : null, o.share ? el('span', { class: 'hc-share', text: o.share }) : null),
        el('div', { class: 'hc-stats' }, dot(setHp), `HP ${fmtN(at.hp, 1)}`, ' · ', dot(setAtk), `ATK ${fmtN(at.atk, 1)}`, others.length ? el('span', { class: 'hc-star', text: ' *', title: 'other stats are overridden' }) : null)));
    const box = el('div', { class: 'hc-block' }, head);
    if (others.length && !o.small) box.appendChild(el('div', { class: 'hc-line others', text: `* also: ${others.slice(0, 8).join(', ')}${others.length > 8 ? ' …' : ''}` }));
    const ranges = rangeLine(st, c);
    if (ranges) box.appendChild(ranges);
    if (!o.small) {
      // the time factor is the row's own, read at its start (pass 58): "time@3:12 1.94"
      const fixed = o.t0 != null && at.arch === 'regular';
      const parts = (ps) => ps.map(([k, v], n) => (n === 0 ? fmtN(v, 2) : `${k === 'time' && fixed ? `time@${fmtT(at.t0)}` : k} ${fmtN(v, 2)}`)).join(' × ');
      box.appendChild(el('div', { class: 'hc-line muted', text: `HP ${parts(at.hpParts)}` }));
      box.appendChild(el('div', { class: 'hc-line muted', text: `ATK ${parts(at.atkParts)} · knock ${fmtN(App.knockbackOf(c, st), 2)} m/s` }));
      const joinedTo = given && given.joined ? App.sourceName(given.joined) : '';
      const halves = given && given.joined ? (given.hpJoined && given.dmgJoined ? 'its HP and ATK' : given.hpJoined ? 'its HP (the damage is the one the event sets, at this second)' : 'its ATK (the HP is the one the event sets, at this second)') : '';
      if (fixed && o.eachFiring) {
        // an "Elites every" event: every firing reads the curves at its own second, or the numbers of a row bringing the
        // same creature then (the review of pass 58, lane WV's fix round)
        const next = Model.eliteEveryTimes(o.eachFiring, 3, App.runEnd()).slice(1).map(fmtT).join(', ');
        box.appendChild(el('div', { class: 'hc-line fixed', text: `Each firing takes the curves at its own second, or the numbers of a row or wave bringing the same creature then: these are the first one's, at ${fmtT(o.t0)}${joinedTo ? ` (it joins ${joinedTo})` : ''}${next ? `; the next about ${next}` : ''}.` }));
      } else if (fixed && joinedTo) {
        box.appendChild(el('div', { class: 'hc-line fixed', text: `Joins ${joinedTo}: while it brings the ${c.name} in the same look, a creature this event sends plays ${halves}, fixed from ${fmtT(at.t0)}.` }));
      } else if (fixed && at.t0 > Math.max(Number(o.t0) || 0, 0) + 1e-9) {
        box.appendChild(el('div', { class: 'hc-line fixed', text: `Fixed afresh from ${fmtT(at.t0)}, the start of this endless wave: in endless every row and wave takes the curves again at each wave (from ${fmtT(o.t0)} before).` }));
      } else if (fixed) {
        const why = [at.row.hpOver ? 'its own HP takes no curve' : '', at.row.dmgOver ? 'its own damage takes no curve' : ''].filter(Boolean).join(', ');
        box.appendChild(el('div', { class: 'hc-line fixed', text: `Fixed from ${fmtT(at.t0)}, the ${o.from || 'row'}'s start: every creature of it has these numbers wherever it spawns in ${App.stageName(at.stage)}${why ? ` (${why})` : ''}; only the stage steps them up, and the hero level at its first spawn.` }));
      }
      // an elite-modified creature (a coloured-elite event, a wave with a modifier) never rolls the variance special
      // pass 69 (lane EN): a swarm set to Special brings every one as its special, for sure
      if (o.forced) {
        const dflt = U.isObj(App.tl().special_defaults) ? App.tl().special_defaults : {};
        const vs = Model.varianceSpecial(c, st, dflt);
        const hasVar = U.isObj(c.variance) && Object.keys(c.variance).length > 0;
        box.appendChild(el('div', { class: 'hc-line fixed', text: hasVar ? `every one comes as its coloured special: HP ${fmtN(at.hp * Model.specialValue(vs.sp, dflt, 'hp'), 1)} · ATK ${fmtN(at.atk * Model.specialValue(vs.sp, dflt, 'damage'), 1)} · size ×${fmtN(vs.size, 2)} · glow ${fmtN(vs.glow, 2)}, even before colour_after_kills` : `${c.name} has no variance block: it comes plain` }));
      } else if (at.special && !o.modded) box.appendChild(el('div', { class: 'hc-line muted', text: `a coloured special (${Math.round(at.special.chance * 100)}% after colour_after_kills${Model.tintRange(st.tint) ? ', a darker shade of the hue it rolled' : ''}): HP ${fmtN(at.special.hp, 1)} · ATK ${fmtN(at.special.atk, 1)}` }));
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
    box.appendChild(creatureBlock(r.enemy, r.variant, r.stats, t, { t0: Number(r.t) || 0, from: 'row' }));
    // pass 81 (lane PACE): a row paced as waves: its waves, the next one, whether it is in the draw at all
    if (Model.rowPaced(r)) {
      const pc = paceChip(r, App.creature(r.enemy));
      const nx = nextRowWave(r, t);
      box.appendChild(el('div', { class: 'hc-line' }, el('b', { text: pc.title }), nx != null ? ` · next wave ${fmtT(nx)}${nx > t ? ` (in ${fmtT(nx - t)})` : ''}` : ' · no wave to come'));
      const gap = Model.rowWaveEvery(r) / Math.max(spp, 1e-9);
      if (Model.rowWaveEvery(r) > 0 && gap < Model.ETCH_MIN_PX) box.appendChild(el('div', { class: 'hc-line muted', text: `its waves are ${fmtN(gap, 1)} px apart at this zoom: every ${Math.ceil(Model.ETCH_MIN_PX / gap)}th tick is drawn; zoom in to see each` }));
    }
    // pass 83 (lane TIMELINE): what this row made of everything spawned in the past N seconds (the estimate)
    box.appendChild(windowLine(winAt(t), `roster:${i}`, 'this row'));
    if (!open || open.drawn) box.appendChild(el('div', { class: 'hc-line muted' }, `${share}${open ? ` · weight ${fmtN(open.w, 2)}` : ''}${open ? ` · ${drawWords(r)}` : ''}`));
    else box.appendChild(el('div', { class: 'hc-line muted' }, `not in the continuous draw · weight ${fmtN(open.w, 2)}${open.w > 0 ? '' : ' (holds its waves)'}`));
    return box;
  }

  function waveCard(i, t) {
    const wv = (App.tl().waves || [])[i];
    if (!wv) return null;
    const end = App.waveEnd(wv);
    const flags = [wv.respect_cap === false ? 'no cap' : '', wv.elite ? `elite ${wv.elite}` : '', wv.channel === 'hell' ? 'hell' : '', wv.toast ? `"${wv.toast}"` : ''].filter(Boolean).join(' · ');
    const box = el('div', {}, cardHead(waveHead(wv), t, `${fmtT(wv.t)} → ${end === Infinity ? 'no end' : fmtT(end)}${flags ? ' · ' + flags : ''}`));
    for (const a of App.waveAlts(wv).slice(0, 6)) box.appendChild(creatureBlock(a.alt.enemy, a.alt.variant, a.alt.stats, t, { small: true, share: `${Math.round(a.share * 100)}%`, t0: Number(wv.t) || 0, from: 'wave' }));
    // pass 83 (lane TIMELINE): what the wave made of everything spawned in the past N seconds
    box.appendChild(windowLine(winAt(t), `wave:${i}:`, 'this wave'));
    const from = Model.fixedFrom(App.tl(), wv.t, t);
    box.appendChild(el('div', { class: 'hc-line fixed', text: from > (Number(wv.t) || 0) + 1e-9
      ? `Its numbers are fixed afresh from ${fmtT(from)}, the start of this endless wave: in endless every row and wave takes the curves again at each wave.`
      : `Its numbers are fixed from ${fmtT(wv.t)}, its start: the same for every creature it sends; only the stage steps them up.` }));
    return box;
  }

  function altCard(i, k, t) {
    const wv = (App.tl().waves || [])[i];
    if (!wv) return null;
    const a = App.waveAlts(wv)[k];
    if (!a) return null;
    const box = el('div', {}, cardHead(a.alt.own ? 'Wave creature' : `Alternative ${k + 1}`, t, `${wv.name || wv.id || 'wave'} · ${Math.round(a.share * 100)}% of the roll${a.alt.pack != null ? ` · packs of ${a.alt.pack}` : ''}`));
    box.appendChild(creatureBlock(a.alt.enemy, a.alt.variant, a.alt.stats, t, { t0: Number(wv.t) || 0, from: 'wave', modded: !!wv.elite }));
    return box;
  }

  function eventCard(i) {
    const ev = (App.tl().events || [])[i];
    if (!ev) return null;
    const t = Number(ev.t) || 0;
    const info = FIELDS.EVENT_TYPES[ev.type];
    const bits = [ev.chance != null && Number(ev.chance) < 1 ? `${Math.round(Number(ev.chance) * 100)}% chance` : '', ev.t_jitter ? `± ${ev.t_jitter} s` : '', ev.type === 'swarm' ? `${ev.count || 40} at once` : '', ev.type === 'swarm' && ev.special ? 'every one its coloured special, no banner' : '', ev.mod ? `modifier ${ev.mod}` : ''].filter(Boolean).join(' · ');
    const box = el('div', {}, cardHead(App.eventLabel(ev), t, (info ? info.label : ev.type) + (bits ? ' · ' + bits : '')));
    const shares = App.eventShares(ev);
    if (shares.length) for (const s of shares.slice(0, 4)) box.appendChild(creatureBlock(s.id, ev.variant, ev.stats, t, { small: shares.length > 1, share: shares.length > 1 ? `${Math.round(s.share * 100)}%` : '', t0: t, from: 'event', event: true, eachFiring: ev.type === 'elite_every' ? ev : null, modded: ev.type === 'elite' || ev.type === 'elite_every', forced: ev.type === 'swarm' && !!ev.special }));
    else if (ev.type === 'elite' || ev.type === 'elite_every') box.appendChild(el('div', { class: 'hc-line muted', text: 'a creature drawn from the roster rows open then, by their Elite weight, wearing a modifier, with that row\'s HP and ATK' }));
    if (shares.length > 1 && ev.type === 'elite_every') box.appendChild(el('div', { class: 'hc-line fixed', text: 'Each firing takes the curves at its own second, or the numbers of a row bringing the same creature then.' }));
    return box;
  }

  function specialsCard(t) {
    const sp = App.tl().specials || {};
    const box = el('div', {}, cardHead('Specials', t, `one at a time from ${fmtT(sp.from)}`));
    for (const row of (sp.pool || []).slice(0, 4)) {
      const id = typeof row === 'string' ? row : row.enemy;
      const st = typeof row === 'string' ? 1 : Number(row.stage || 1);
      // a special's numbers are the second it comes, or a row's bringing the same creature then (lane WV's fix round)
      box.appendChild(creatureBlock(id, '', null, t, { small: true, share: st > 1 ? `from stage ${st}` : '', t0: t, event: true }));
    }
    return box;
  }

  // ------------------------------------------------------------------ the window's shares (pass 83, lane TIMELINE)

  // Garry (2026-10-16): "if I hover over enemies and specifically over those yellow notches it actually shows the % of
  // enemies that will be spawning ... the highlight actually just shows the share of roster draw as the % of enemies that
  // spawned in the past 5 seconds (controllable value next to 'snap on') with a hint explaining what that value is.
  // Remove the 'Share section'". Every share here is read off the Spawned so far estimate (Model.windowShares): the
  // director's rules played second by second (the cap, the weights, the spawn check and the rows' own clocks, the waves,
  // the kill rate), so a waves row counts what its waves really bring and a row the cap starves counts little.

  /** The map's spawn check in seconds (Settings → Spawning). */
  function spawnCheck() {
    const si = App.tl().spawn_interval;
    return si == null || si === '' ? 0.5 : Number(si);
  }

  /** The window box next to Snap on: whole seconds WIN_MIN..WIN_MAX, remembered by the browser. */
  function wireWindow() {
    const inp = document.getElementById('win-secs');
    if (!inp || inp.dataset.wired) return;
    inp.dataset.wired = '1';
    inp.value = String(winSecs);
    inp.addEventListener('change', () => setWindow(inp.value));
    inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') inp.blur(); e.stopPropagation(); });
  }
  function setWindow(v) {
    const n = Math.round(Number(v));
    winSecs = n >= WIN_MIN ? Math.min(n, WIN_MAX) : WIN_DEF;
    try { localStorage.setItem(WIN_KEY, String(winSecs)); } catch (_) { /* fine */ }
    const inp = document.getElementById('win-secs');
    if (inp) inp.value = String(winSecs);
    return winSecs;
  }

  /** The estimate's shares in the `winSecs` before run second t, or in the `winSecs` from t (`ahead`: a wave's tick,
   *  read from the second before it so its own second counts); null before the estimate is drawn. */
  function winAt(t, ahead) {
    const est = lastSpawn ? lastSpawn.est : null;
    if (!est) return null;
    return ahead ? Model.windowShares(est, t - 1e-6, t + winSecs - 1e-6) : Model.windowShares(est, t - winSecs, t);
  }
  /** A key's spawns in a window: an exact key ('roster:3'), or every key under a prefix ending in ':' ('wave:2:'). */
  function winCount(win, key) {
    if (!win) return 0;
    if (!key.endsWith(':')) return win.src[key] || 0;
    let n = 0;
    for (const k of Object.keys(win.src)) if (k.startsWith(key)) n += win.src[k];
    return n;
  }
  const pctText = (f) => (f > 0 && f < 0.005 ? '<1%' : `${Math.round(f * 100)}%`);
  /** "34% of the 52 creatures spawned in the past 5 s (2:00–2:05), ≈18 from this row". */
  function windowLine(win, key, who) {
    if (!win) return el('div', { class: 'hc-line muted', text: 'the share of what spawns comes from the Spawned so far estimate (not drawn yet)' });
    const n = winCount(win, key);
    const f = win.all > 0 ? n / win.all : 0;
    return el('div', { class: 'hc-line win-line' }, el('b', { text: `${pctText(f)} of the creatures spawned` }),
      ` in ${fmtT(win.t0)}–${fmtT(win.t1)}: ≈${fmtCount(n)} from ${who} of ≈${fmtCount(win.all)} in all`,
      el('small', { text: ` (the past ${winSecs} s, the box next to Snap; an estimate)` }));
  }
  /** How a drawn row's draws come: at the spawn check, or on its own clock. */
  function drawWords(r) {
    if (!Model.rowDrawn(r)) return 'comes as waves only';
    const si = spawnCheck();
    return Model.rowHasInterval(r) ? `drawn on its own clock every ${fmtN(Model.rowDrawInterval(r, si), 2)} s` : `drawn at the spawn check every ${fmtN(si, 2)} s`;
  }

  /** The tick nearest `t` within 8 px in `times`, or null. */
  function nearestTick(times, t) {
    let best = null;
    for (const tk of times) if (Math.abs(tk - t) <= 8 * spp && (best == null || Math.abs(tk - t) < Math.abs(best - t))) best = tk;
    return best;
  }

  /** A roster bar's foot (pass 83): the wave tick nearest the pointer (its count and its share of the N s from it), else
   *  the draw nearest it (how often, what a draw holds, the share of the past N s), else the row's card. */
  function etchCard(i, t) {
    const r = (App.tl().roster || [])[i];
    if (!r) return null;
    const lateT = App.tl().weight_late_t;
    const end = r.until == null || r.until === '' ? App.viewEnd() : Number(r.until);
    const c = App.creature(r.enemy);
    const name = c ? c.name : r.enemy;
    if (Model.rowPaced(r)) {
      const tw = nearestTick(Model.rowEtchTimes(r, Math.min(end, t + 8 * spp), lateT).filter((tk) => tk >= t - 8 * spp), t);
      if (tw != null) {
        const n = Model.rowWaveCount(r, c);
        const pc = paceChip(r, c);
        const box = el('div', {}, cardHead('Wave', tw, `${name} · ${pc.text} · row ${i + 1}`));
        box.appendChild(el('div', { class: 'hc-line' }, el('b', { text: `${n} × ${name}` }), r.respect_cap === false ? ' at once, on top of the cap' : ' into the free room under the cap; the rest as room frees, until the next wave'));
        const win = winAt(tw, true);
        if (win) {
          const came = winCount(win, `roster:${i}`);
          const f = win.all > 0 ? came / win.all : 0;
          box.appendChild(el('div', { class: 'hc-line win-line' }, el('b', { text: `${pctText(f)} of the creatures spawned in the ${winSecs} s from ${fmtT(tw)}` }), `: ≈${fmtCount(came)} from this row of ≈${fmtCount(win.all)} in all${r.respect_cap !== false && came < n - 0.5 ? ` (the cap let ≈${fmtCount(came)} of its ${n} in by then)` : ''}`));
        }
        return box;
      }
    }
    if (Model.rowDrawn(r)) {
      const si = spawnCheck();
      const iv = Model.rowDrawInterval(r, si);
      const td = nearestTick(Model.rowDrawTimes(r, Math.max(0, t - 8 * spp), Math.min(end, t + 8 * spp), si, lateT), t);
      if (td != null) {
        const tl = App.tl();
        const lo = tl.burst_min == null ? 5 : Number(tl.burst_min), hi = tl.burst_max == null ? 20 : Number(tl.burst_max);
        const open = App.rosterAt(td).find((o) => o.i === i);
        const sh = open ? open.norm : 0;
        const box = el('div', {}, cardHead('Draw', td, `${name} · ${drawWords(r)} · row ${i + 1}`));
        box.appendChild(el('div', { class: 'hc-line' }, el('b', { text: `≈${fmtN(((lo + hi) / 2) * sh, 1)} load units a draw` }), ` while the cap has room: a burst of ${lo}–${hi} × its ${pctText(sh)} of the open rows' weight${Model.rowHasInterval(r) ? '' : ', shared at the spawn check with the other rows'}`));
        box.appendChild(windowLine(winAt(td), `roster:${i}`, 'this row'));
        const gap = iv / Math.max(spp, 1e-9);
        if (gap < Model.ETCH_MIN_PX) box.appendChild(el('div', { class: 'hc-line muted', text: `its draws are ${fmtN(gap, 1)} px apart at this zoom: drawn as a dotted line; zoom in (+) past ${fmtN(Model.ETCH_MIN_PX / iv, 1)} px a second to see each tick` }));
        if (!Model.rowHasInterval(r)) box.appendChild(el('div', { class: 'hc-line muted', text: 'the spawn check runs on through boss fights, so later in a run its ticks are its rhythm rather than its exact seconds' }));
        return box;
      }
    }
    return rosterCard(i, t);
  }

  /** A waves block's foot (pass 83): the burst nearest the pointer, its size and its share of the N s from it. */
  function burstCard(i, t) {
    const wv = (App.tl().waves || [])[i];
    if (!wv) return null;
    const tb = nearestTick(Model.waveBurstTimes(wv, t + 8 * spp).filter((tk) => tk >= t - 8 * spp), t);
    if (tb == null) return waveCard(i, t);
    const box = el('div', {}, cardHead('Burst', tb, `${waveHead(wv)} · ${Math.max(1, Number(wv.burst) || 5)} a burst${Number(wv.count) > 0 ? ` of ${wv.count}` : ''}`));
    const win = winAt(tb, true);
    if (win) {
      const n = winCount(win, `wave:${i}:`);
      box.appendChild(el('div', { class: 'hc-line win-line' }, el('b', { text: `${pctText(win.all > 0 ? n / win.all : 0)} of the creatures spawned in the ${winSecs} s from ${fmtT(tb)}` }), `: ≈${fmtCount(n)} from this wave of ≈${fmtCount(win.all)} in all`));
    }
    return box;
  }

  /** The highlight on the lane (pass 83): while the pointer is on the timeline, the roster bars that spawned nothing in
   *  the past N seconds dim, so the ones bright are the ones spawning. `t` null clears it. */
  let lastHover = null;
  function lightRows(t) {
    lastHover = t;
    const svgEl = lanes.roster ? lanes.roster.svg : null;
    if (!svgEl) return;
    const win = t == null ? null : winAt(t);
    for (const g of svgEl.querySelectorAll('g.bar[data-key^="roster:"]')) {
      const key = g.getAttribute('data-key');
      g.classList.toggle('win-zero', !!win && !(winCount(win, key) > 1e-6));
    }
  }

  // ------------------------------------------------------------------ cursor, readout, cards

  function onHover(e) {
    if (drag || !App.S.map) return;
    const t = tAt(e.clientX);
    if (t < 0 || e.clientX < svgLeft()) { hideCursor(); return; }
    cursorEl.hidden = false;
    cursorEl.style.left = `${LABEL_W + x(t)}px`;
    App.setClock(t);
    lightRows(Math.max(0, t));
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
    lightRows(null);
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
    readout.appendChild(el('div', { class: 'ro-line' }, `HP ×${fmtN(hp.total, 2)}`, el('small', { text: ` (a row starting now: time ${fmtN(hp.time, 2)} × stage ${fmtN(hp.stage, 2)} × level ${fmtN(hp.level, 2)} × creature ${fmtN(hp.creature, 2)})` })));
    readout.appendChild(el('div', { class: 'ro-line' }, `ATK ×${fmtN(dm.total, 2)}`, el('small', { text: ` (time ${fmtN(dm.time, 2)} × stage ${fmtN(dm.stage, 2)} × level ${fmtN(dm.level, 2)} × creature ${fmtN(dm.creature, 2)})` })));
    // pass 58: what the rows spawning now really carry (each fixed from its own start)
    const ser = lastActual ? lastActual.series : null;
    const si = ser ? Math.max(0, Math.min(ser.ts.length - 1, Math.round(t))) : -1;
    if (ser && si >= 0 && ser.hp.avg[si] != null) {
      readout.appendChild(el('div', { class: 'ro-line' }, `actual HP ${fmtX(ser.hp.avg[si])} · ${fmtX(ser.hp.max[si])} max`, el('small', { text: ` · ATK ${fmtX(ser.atk.avg[si])} · ${fmtX(ser.atk.max[si])} max (the rows spawning now, each fixed from its start)` })));
    }
    readoutShares(t);
    const ws = App.wavesAt(t);
    if (ws.length) {
      readout.appendChild(el('div', { class: 'ro-title', text: 'Waves running' }));
      for (const { w } of ws) readout.appendChild(el('div', { class: 'ro-line', text: `${w.name || w.id}: ${w.count || '∞'} in ${w.burst == null ? 5 : w.burst}s every ${w.every == null ? 2 : w.every} s${w.respect_cap === false ? ' (no cap)' : ''}` }));
    }
    const nx = App.nextEvent(t);
    if (nx) readout.appendChild(el('div', { class: 'ro-line' }, 'next: ', el('b', { text: App.eventLabel(nx.ev) }), ` at ${fmtT(nx.t)} (in ${fmtT(nx.t - t)})`));
    place(readout, cx, cy);
  }

  /** The readout's roster block (pass 83, lane TIMELINE): every roster row's and wave's share of the creatures spawned in
   *  the past N seconds (the estimate), largest first; the rows open now that spawned nothing there dimmed, with their
   *  next wave when they come as waves; then everything else (swarms, Elites, specials, bosses). */
  function readoutShares(t) {
    const win = winAt(t);
    const rowsAll = App.tl().roster || [];
    const open = App.rosterAt(t);
    readout.appendChild(el('div', { class: 'ro-title', title: WIN_HELP }, `Spawned in the past ${winSecs} s`, el('small', { text: win ? ` ${fmtT(win.t0)}–${fmtT(win.t1)} · ≈${fmtCount(win.all)} creatures` : '' })));
    if (!win) { readout.appendChild(el('div', { class: 'ro-line muted', text: 'the estimate is not drawn yet' })); return; }
    const items = [];
    const seen = new Set();
    rowsAll.forEach((r, i) => {
      const n = winCount(win, `roster:${i}`);
      const o = open.find((x) => x.i === i);
      if (!(n > 1e-6) && !o) return;
      seen.add(i);
      items.push({ n, id: r.enemy, variant: r.variant, hell: r.channel === 'hell', paced: Model.rowPaced(r), r, label: App.creatureName(r.enemy) });
    });
    (App.tl().waves || []).forEach((wv, i) => {
      const n = winCount(win, `wave:${i}:`);
      if (n > 1e-6) items.push({ n, id: wv.enemy || ((wv.alts || [])[0] || {}).enemy, wave: true, label: waveHead(wv) });
    });
    items.sort((p, q) => q.n - p.n || (p.label < q.label ? -1 : 1));
    const chart = el('div', { class: 'ro-chart' });
    for (const it of items) {
      const f = win.all > 0 ? it.n / win.all : 0;
      const nx = it.paced ? nextRowWave(it.r, t) : null;
      const tag = it.wave ? ' (wave)' : it.paced ? (nx != null ? ` · waves, next ${fmtT(nx)}` : ' · waves') : '';
      chart.appendChild(el('div', { class: 'ro-row' + (it.hell ? ' hell' : '') + (it.n > 1e-6 ? '' : ' zero'), title: `≈${fmtCount(it.n)} of ≈${fmtCount(win.all)}` },
        it.id && App.creature(it.id) ? el('img', { src: App.iconFor(it.id, it.variant), width: 16, height: 16 }) : el('span', { class: 'ro-ico' }),
        el('span', { class: 'ro-name' }, it.label, el('small', { text: tag })),
        el('span', { class: 'ro-bar' }, el('i', { style: `width:${Math.round(f * 100)}%;background:${it.id ? App.creatureColor(it.id) : '#888'}` })),
        el('span', { class: 'ro-pct', text: pctText(f) })));
    }
    if (win.other > 0.05) {
      const f = win.all > 0 ? win.other / win.all : 0;
      chart.appendChild(el('div', { class: 'ro-row other', title: 'swarms, the elite-modified, specials, Elites, bosses, a boss\'s minions and the portal wave' },
        el('span', { class: 'ro-ico' }), el('span', { class: 'ro-name', text: 'swarms, Elites, specials …' }),
        el('span', { class: 'ro-bar' }, el('i', { style: `width:${Math.round(f * 100)}%;background:#888` })), el('span', { class: 'ro-pct', text: pctText(f) })));
    }
    if (items.length || win.other > 0.05) readout.appendChild(chart);
    else readout.appendChild(el('div', { class: 'ro-line muted', text: open.length ? 'nothing spawned in that window' : 'no roster row open' }));
  }

  return { mount, render, fit, zoom, viewCenter, scrollToSelection, hideCard, LABEL_W, ALT_COLORS, get spp() { return spp; }, setSnap, toggleSnap, get snapOn() { return snapOn; }, setWindow, get winSecs() { return winSecs; } };
})();
