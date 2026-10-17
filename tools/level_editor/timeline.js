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
  // pass 87 (lane STOOLS): the strip of stage tabs above the sections (stage_tabs.js draws it)
  let stageBar = null;
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

  // pass 84 (lane TIMELINE): every lane's title, its "+" button, its class and its tooltip; the sections (FIELDS.SECTIONS)
  // say which lanes each holds, in order
  const LANE_SPEC = {
    ruler: ['Time', null, 'ruler', ''],
    alive: ['On screen', null, '', 'creatures alive at each second: the estimate, the Sim, the cap in bodies, the floor (FIELDS.LANES: alive)'],
    challenge: ['To clear', null, '', 'seconds of the hero\'s damage to clear the screen (FIELDS.LANES: challenge)'],
    composition: ['Composition', null, '', 'who the crowd is made of, % (FIELDS.LANES: composition)'],
    cap: ['Cap', null, '', CAP_HELP],
    floor: ['Floor', { text: '+ Floor', title: 'start a floor curve (the least creatures alive) at 20 from 0:00', onclick: () => addFloor() }, '', 'the floor curve: the least creatures alive on the regular channel (floor_curve); click to edit, drag its points, double-click to add or remove one'],
    spawned: ['Spawned so far', null, '', SPAWN_HELP],
    hp_act: ['Actual HP ×', null, '', ACT_HELP.hp],
    hp: ['HP ×', null, '', 'Creature health over the run clock (hp_curve): click to edit the curve, drag its points, double-click to add or remove one. Since pass 58 a row reads it once, at its start.'],
    dmg_act: ['Actual ATK ×', null, '', ACT_HELP.dmg],
    dmg: ['ATK ×', null, '', 'Creature damage over the run clock (damage_curve): click to edit, drag its points, double-click to add or remove one. Since pass 58 a row reads it once, at its start.'],
    roster: ['Rows', { text: '+ Row', title: 'Add a spawn row at the view\'s centre: continuous, waves, once (a swarm), a coloured elite, Elites every…', onclick: (e) => rowMenu(e.currentTarget) }, '', ''],
    waves: ['Waves (old)', { text: '+ Wave', title: 'Add a wave block at the view\'s centre (the old waves[] list; a row paced as Waves does the same)', onclick: () => App.newWave(null, viewCenter()) }, '', ''],
    events: ['Events', { text: '+ Event', title: 'Add a boss or an Elite mini-boss at the view\'s centre', onclick: (e) => eventMenu(e.currentTarget) }, '', ''],
    specials: ['Specials', null, '', ''],
    paths: ['Mutations', null, '', 'When each stage\'s mutation offers fall due; each comes at the hero\'s next level-up (pass 79).'],
  };
  const sections = {};                 // id -> {root, head, bar, body, sum, ctl}

  function mount(container) {
    root = container;
    clear(root);
    scrollBox = el('div', { class: 'tl-scroll' });
    content = el('div', { class: 'tl-content' });
    scrollBox.appendChild(content);
    // the ruler first and always (sticky at the top); then the sections, each a header bar and its lanes
    addLane(content, 'ruler');
    for (const sec of FIELDS.SECTIONS) {
      const s = buildSection(sec);
      content.appendChild(s.root);
      for (const name of sec.lanes) addLane(s.body, name);
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
    // pass 87 (lane STOOLS): the stage tabs above the calendar
    stageBar = el('div', { class: 'tl-stagebar' });
    root.appendChild(stageBar);
    root.appendChild(scrollBox);
    // pass 84: the inspector folds to a slim bar at the right (its own state, remembered by the browser)
    wireInspectorFold();
    scrollBox.addEventListener('pointermove', onHover);
    scrollBox.addEventListener('pointerleave', () => { if (!drag) hideCursor(); });
    scrollBox.addEventListener('scroll', () => { if (lastHover) lightRows(null); });
    scrollBox.addEventListener('wheel', onWheel, { passive: false });
    scrollBox.addEventListener('pointerdown', (e) => { if (e.target === content || e.target === scrollBox || e.target.classList.contains('lane-svg')) { if (e.button === 0) App.select(null); } });
    // pass 85 (lane TOOLS): the right button pans the Spawn rows (capture: no bar ever sees it), no context menu there
    scrollBox.addEventListener('pointerdown', onPanDown, true);
    scrollBox.addEventListener('contextmenu', (e) => { if (inPanArea(e.target) || pan || performance.now() - panEndT < 400) e.preventDefault(); });
    window.addEventListener('resize', () => { if (App.S.map && App.S.tab === 'timeline') render(); });
  }

  // ------------------------------------------------------------------ the right-button pan (pass 85)

  // Garry (2026-10-17): "Timeline - make it possible to pan around with right click when inside the Rows area." Inside the
  // Spawn rows section (its lanes and their labels), holding the right mouse button and dragging moves the view with the
  // pointer, both ways: time left and right, the rows up and down (the scroll box's own scroll, so the ruler and the
  // sections' bars stay where they are). A grab cursor while it lasts; no context menu there; it never edits a bar (the
  // press is taken in the capture phase, before any bar's handler); a click without a drag does nothing.
  const PAN_AREA = '.tl-sec-rows .tl-sec-body';
  let pan = null;                      // {id, x, y, left, top, moved} while the right button pans
  let panEndT = 0;
  function inPanArea(t) { return !!(t && t.closest && t.closest(PAN_AREA)); }
  /** The scroll a pan that started at `p` (its pointer and its scroll) asks for with the pointer at (cx, cy): the content
   *  follows the pointer (pure; the selftest reads it). */
  function panTo(p, cx, cy) { return { left: Math.max(0, p.left - (cx - p.x)), top: Math.max(0, p.top - (cy - p.y)) }; }
  function onPanDown(e) {
    if (e.button !== 2 || drag || pan || !inPanArea(e.target)) return;
    e.preventDefault();
    e.stopPropagation();
    hideCursor();
    pan = { id: e.pointerId, x: e.clientX, y: e.clientY, left: scrollBox.scrollLeft, top: scrollBox.scrollTop, moved: false };
    try { scrollBox.setPointerCapture(e.pointerId); } catch (_) { /* the window's listeners still follow */ }
    document.body.classList.add('tl-panning');
    window.addEventListener('pointermove', onPanMove, true);
    window.addEventListener('pointerup', onPanUp, true);
    window.addEventListener('pointercancel', onPanUp, true);
  }
  function onPanMove(e) {
    if (!pan || e.pointerId !== pan.id) return;
    e.preventDefault();
    e.stopPropagation();
    if (Math.abs(e.clientX - pan.x) + Math.abs(e.clientY - pan.y) > 2) pan.moved = true;
    const to = panTo(pan, e.clientX, e.clientY);
    scrollBox.scrollLeft = to.left;
    scrollBox.scrollTop = to.top;
  }
  function onPanUp(e) {
    if (!pan || e.pointerId !== pan.id) return;
    try { scrollBox.releasePointerCapture(pan.id); } catch (_) { /* gone already */ }
    pan = null;
    panEndT = performance.now();
    document.body.classList.remove('tl-panning');
    window.removeEventListener('pointermove', onPanMove, true);
    window.removeEventListener('pointerup', onPanUp, true);
    window.removeEventListener('pointercancel', onPanUp, true);
  }

  /** One lane: its sticky label (an eye on a view-only lane, a pencil on an editing one; pass 84) and its SVG. */
  function addLane(parent, name) {
    const [title, plus, cls, help] = LANE_SPEC[name];
    const kind = name === 'ruler' ? '' : FIELDS.VIEW_LANES.includes(name) ? 'view' : 'edit';
    const head = name === 'roster' ? el('div', { class: 'lane-head' }, el('div', {}, el('div', { class: 'lane-name' }, kindMark(kind, true), title), el('div', { class: 'lane-sub' }))) : null;
    const label = head
      ? el('div', { class: 'lane-label roster-label' }, head, el('div', { class: 'gutter' }))
      : el('div', { class: 'lane-label', title: help }, el('div', { class: 'lane-name' }, kind ? kindMark(kind, true) : null, title), el('div', { class: 'lane-sub' }));
    if (plus) (head || label).appendChild(el('button', { class: 'btn small plus', text: plus.text, title: plus.title, onclick: plus.onclick }));
    const s = svg('svg', { class: 'lane-svg', height: 10 });
    const row = el('div', { class: 'lane lane-' + name + (cls ? ' ' + cls : '') + (kind ? ' lane-' + kind : '') }, label, s);
    label.addEventListener('click', (e) => {
      if (e.target.tagName === 'BUTTON' || e.target.closest('.gutter') || e.target.closest('.sp-ctl')) return;
      if (['cap', 'floor', 'hp', 'dmg', 'specials', 'paths'].includes(name)) App.select({ kind: name });
      // an Actual lane opens its curve's inspector, which compares the two (pass 58)
      if (name === 'hp_act' || name === 'dmg_act') App.select({ kind: name === 'hp_act' ? 'hp' : 'dmg' });
    });
    parent.appendChild(row);
    lanes[name] = { row, label, svg: s };
  }

  // ------------------------------------------------------------------ sections (pass 84)

  // Garry (2026-10-16): "allow for the option to collapse some sections so they don't get in the way. Make sure that this
  // functionality uses good ui so it's easy to tell where a section was collapsed. Mark somehow (in a subtle way) which
  // sections are view only, and which are tools for editing things." Each section is a header bar (a chevron, the mark,
  // the name, what it is, its own controls) over its lanes; collapsed, the bar stays where the section was, hatched, with
  // a summary of what it holds and "collapsed: click to open". The browser remembers each map's sections.
  const SEC_KEY = (map) => `88fits-editor-sections-${map || ''}`;
  let secState = {};                   // id -> true when collapsed ('group:<key>' for the spawn rows' groups too)
  let secMap = null;

  function loadSecState() {
    const id = App.S.mapId || '';
    if (secMap === id) return;
    secMap = id;
    secState = {};
    try { const v = JSON.parse(localStorage.getItem(SEC_KEY(id)) || 'null'); if (v && typeof v === 'object') secState = v; } catch (_) { /* fresh */ }
  }
  function saveSecState() { try { localStorage.setItem(SEC_KEY(secMap), JSON.stringify(secState)); } catch (_) { /* fine */ } }
  const isCollapsed = (id) => !!secState[id];
  function setCollapsed(id, on) {
    if (on) secState[id] = true; else delete secState[id];
    saveSecState();
    render();
  }
  /** Collapse or open every section (and every group of the spawn rows). */
  function setAll(on) {
    for (const sec of FIELDS.SECTIONS) if (on) secState[sec.id] = true; else delete secState[sec.id];
    if (!on) for (const k of Object.keys(secState)) if (k.startsWith('group:')) delete secState[k];
    saveSecState();
    render();
  }

  /** The kind mark: an eye (view only) or a pencil (editing); `small` for a lane's label. */
  function kindMark(kind, small) {
    if (!kind) return null;
    const words = kind === 'view' ? 'view only: drawn from the map, the estimate and the Sim; nothing here changes the map' : 'editing: drag, click and type here to change the map';
    return el('span', { class: 'kmark kmark-' + kind + (small ? ' small' : ''), title: words }, U.glyph(kind === 'view' ? 'eye' : 'pencil'));
  }

  function buildSection(sec) {
    const sum = el('span', { class: 'tl-sec-sum' });
    const ctl = el('span', { class: 'tl-sec-ctl' });
    const hint = el('span', { class: 'tl-sec-hint' });
    const bar = el('div', { class: 'tl-sec-bar' },
      el('span', { class: 'tl-chev', text: '▾' }), kindMark(sec.kind),
      el('b', { class: 'tl-sec-name', text: sec.name }), el('span', { class: 'tl-sec-what', text: sec.what }), sum,
      el('span', { class: 'spacer' }), ctl, hint);
    const head = el('div', { class: 'tl-sec-head', role: 'button', tabindex: 0, 'aria-expanded': 'true', title: `${sec.name}: click to collapse or open` }, bar);
    const toggle = () => setCollapsed(sec.id, !isCollapsed(sec.id));
    head.addEventListener('click', (e) => { if (e.target.closest('.tl-sec-ctl')) return; toggle(); });
    head.addEventListener('keydown', (e) => { if ((e.key === 'Enter' || e.key === ' ') && !e.target.closest('.tl-sec-ctl')) { e.preventDefault(); toggle(); } });
    const body = el('div', { class: 'tl-sec-body' });
    const rootEl = el('div', { class: `tl-sec tl-sec-${sec.id} kind-${sec.kind}`, 'data-sec': sec.id }, head, body);
    const s = { sec, root: rootEl, head, bar, body, sum, ctl, hint };
    sections[sec.id] = s;
    buildSectionControls(s);
    return s;
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
  // pass 87 (lane STOOLS): the axis starts at the view's start T0 (0 on "All", the window's start on a stage tab), so a
  // stage tab draws its window from the left edge; times stay run-clock seconds everywhere (the map's own clock)
  let T0 = 0;
  const x = (t) => (t - T0) / spp;
  const tAt = (clientX) => (clientX - svgLeft()) * spp + T0;
  /** The run second at pixel `px` of a lane (the sampled lines walk the pixels). */
  const tAtPx = (px) => px * spp + T0;
  const contentWidth = () => Math.ceil((App.viewEnd() - T0) / spp) + 60;

  function viewCenter() {
    if (!scrollBox) return T0;
    const visible = scrollBox.clientWidth - LABEL_W;
    const hi = App.viewStage() == null ? App.runEnd() : App.stageEnd(App.viewStage());
    return Math.max(T0, Math.min(hi, tAtPx(scrollBox.scrollLeft + visible / 2)));
  }

  function fit() {
    if (!scrollBox) return;
    const w = Math.max(200, scrollBox.clientWidth - LABEL_W - 40);
    T0 = App.viewStart();
    spp = (App.viewEnd() - T0) / w;
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
      // a row low on a long roster: bring it into view vertically too (pass 84: its section and its group opened first)
      const r = (App.tl().roster || [])[sel.i];
      if (r && (isCollapsed('rows') || isCollapsed('group:' + groupOf(r, prefs.group).key))) {
        delete secState.rows; delete secState['group:' + groupOf(r, prefs.group).key];
        saveSecState();
        render();
      }
      const yy = rosterLay && rosterLay.yOf[sel.i] != null ? rosterLay.yOf[sel.i] : ROSTER_HEAD + sel.i * ROW_H;
      const top = lanes.roster.row.getBoundingClientRect().top - content.getBoundingClientRect().top + yy;
      if (top < scrollBox.scrollTop + RULER_H || top + ROW_H > scrollBox.scrollTop + scrollBox.clientHeight) scrollBox.scrollTop = Math.max(0, top - scrollBox.clientHeight / 3);
    }
  }

  // ------------------------------------------------------------------ the "+ Event" menu

  function eventMenu(anchor) {
    closeMenu();
    menu = el('div', { class: 'menu' });
    // pass 84 (lane TIMELINE): one spawning language: swarms, coloured elites and Elites every are spawn rows now (+ Row);
    // the events keep the bosses and the Elite mini-bosses
    for (const [type, info] of Object.entries(FIELDS.EVENT_TYPES)) {
      if (type !== 'boss' && type !== 'elite_boss') continue;
      menu.appendChild(el('button', { class: 'menu-item', onclick: () => { closeMenu(); App.newEvent(type, viewCenter()); } }, glyph(info.glyph), el('span', { text: info.label }), el('small', { text: info.help })));
    }
    menu.appendChild(el('div', { class: 'menu-note', text: 'Swarms, coloured elites and Elites every are spawn rows now: + Row in Spawn rows.' }));
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
    // pass 87: the stage tab strip and the axis's start (a stage tab: its window)
    T0 = App.viewStart();
    renderStageTabs();
    loadSecState();
    hovers = {};
    if (!drag) hideCard();
    const w = contentWidth();
    content.style.width = `${LABEL_W + w}px`;
    // the section bars, the controls strip and the warnings stay in view while the lanes scroll sideways (pass 84)
    content.style.setProperty('--vis-w', `${Math.max(320, scrollBox.clientWidth)}px`);
    for (const name of Object.keys(lanes)) lanes[name].svg.setAttribute('width', w);
    renderRuler(w);
    // the estimate once a render: every view lane, the Spawned so far lane and the Actual lanes' weights (pass 58)
    const res = App.spawned(!!drag);
    lastSpawn = res;
    lastActual = App.actual(res);
    view = viewOf(res);
    const open = (id) => !isCollapsed(id);
    if (open('onscreen')) renderAlive(w);
    if (open('challenge')) renderChallenge(w);
    if (open('composition')) renderComposition(w);
    if (open('spawned')) renderSpawned(w, res); else syncSpawnControls();
    if (open('rows')) { renderRoster(w); renderWaves(w); }
    if (open('events')) { renderEvents(w); renderSpecials(w); renderPaths(w); }
    if (open('curves')) {
      renderCap(w);
      renderFloor(w);
      renderActual(w, 'hp_act', true);
      renderCurve(w, 'hp', 'hp_curve');
      renderActual(w, 'dmg_act', false);
      renderCurve(w, 'dmg', 'damage_curve');
    }
    if (open('warnings')) renderWarnings();
    syncSections();
    const selKey = App.selKey();
    for (const name of ['cap', 'floor', 'hp', 'dmg', 'specials', 'paths']) lanes[name].row.classList.toggle('selected', selKey === name);
    lanes.hp_act.row.classList.toggle('selected', selKey === 'hp');
    lanes.dmg_act.row.classList.toggle('selected', selKey === 'dmg');
    updateZoomLabel();
  }

  /** Pass 87 (lane STOOLS): the stage tab strip (StageTabs.renderStrip), drawn with the rest. */
  function renderStageTabs() {
    if (stageBar && typeof StageTabs !== 'undefined') StageTabs.renderStrip(stageBar);
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

  // ------------------------------------------------------------------ the sections' controls and words (pass 84)

  let view = null;                     // viewOf(): the view lanes' numbers for the estimate drawn last
  /** The Challenge lane's zones for the measure shown. */
  const zonesNow = () => zoneSets[prefs.chal === 'bars' ? 'bars' : 'seconds'];
  // the Challenge lane's zone limits per measure (seconds to clear the screen; health bars lost clearing it): a page
  // setting the browser remembers
  const ZONE_KEY = '88fits-editor-zones84';
  const zoneSets = { seconds: Object.assign({}, TimelineModel.ZONES), bars: Object.assign({}, TimelineModel.BAR_ZONES) };
  try {
    const z = JSON.parse(localStorage.getItem(ZONE_KEY) || 'null');
    if (z && typeof z === 'object') for (const k of ['seconds', 'bars']) if (z[k] && z[k].easy > 0 && z[k].hard > z[k].easy) zoneSets[k] = { easy: Number(z[k].easy), hard: Number(z[k].hard) };
  } catch (_) { /* the defaults */ }
  // how the spawn rows are grouped and coloured, the Composition lane's mode and source: page settings
  const PREF_KEY = '88fits-editor-tlprefs';
  const prefs = { group: 'stage', colour: 'role', comp: 'alive', compSrc: 'est', chal: 'seconds' };
  try { const v = JSON.parse(localStorage.getItem(PREF_KEY) || 'null'); if (v && typeof v === 'object') for (const k of Object.keys(prefs)) if (typeof v[k] === 'string') prefs[k] = v[k]; } catch (_) { /* the defaults */ }
  function setPref(k, v) {
    prefs[k] = v;
    try { localStorage.setItem(PREF_KEY, JSON.stringify(prefs)); } catch (_) { /* fine */ }
    render();
  }
  const GROUP_MODES = [
    { v: 'stage', label: 'by stage', help: 'a group per stage the row starts in' },
    { v: 'role', label: 'by role', help: 'a group per role (the row form\'s Role; untagged rows together)' },
    { v: 'stage_role', label: 'by stage and role', help: 'a group per stage and role' },
    { v: 'none', label: 'no groups', help: 'every row in the file\'s order (the grip at the left reorders them)' },
  ];
  const COLOUR_MODES = [
    { v: 'role', label: 'by role', help: 'each bar in its role\'s colour (the legend in the section; untagged = grey)' },
    { v: 'creature', label: 'by creature', help: 'each bar in its creature\'s colour (the same colours as the Composition lane)' },
  ];

  /** A small <select> for the section bars: `opts` [{v, label, help}], the current value, the change. */
  function miniSelect(opts, value, onChange, title) {
    const sel = el('select', { class: 'mini-sel', title: title || '' });
    for (const o of opts) sel.appendChild(el('option', { value: o.v, text: o.label, title: o.help || '' }));
    sel.value = value;
    sel.addEventListener('change', () => onChange(sel.value));
    sel.addEventListener('click', (e) => e.stopPropagation());
    return sel;
  }
  /** A swatch and its words for a legend. */
  const lg = (cls, text, title) => el('span', { class: 'lg-item', title: title || '' }, el('i', { class: 'lg-sw ' + cls }), text);

  /** The "What is this?" strip of a view section (pass 84; Garry: "I won't know what intensity means unless there is
   *  some way for me to clearly read somewhere what it consists of"): one line, a legend naming every line, and a box with
   *  the exact recipe and units (TimelineModel.RECIPES). */
  function explainStrip(id, legend) {
    const R = TimelineModel.RECIPES[id === 'challenge' && prefs.chal === 'bars' ? 'challenge_bars' : id];
    const lines = el('div', { class: 'tl-recipe' });
    for (const [name, text] of R.lines) lines.appendChild(el('div', { class: 'tl-recipe-line' }, el('b', { text: `${name}: ` }), text));
    const det = el('details', { class: 'tl-how', 'data-how': id }, el('summary', { text: 'How it is worked out (the recipe and the units)' }), lines);
    if (secState['how:' + id]) det.open = true;
    det.addEventListener('toggle', () => { if (det.open) secState['how:' + id] = true; else delete secState['how:' + id]; saveSecState(); });
    return el('div', { class: 'tl-strip tl-explain', 'data-explain': id },
      el('div', { class: 'tl-what' }, el('b', { text: 'What is this? ' }), el('span', { text: R.what })),
      el('div', { class: 'tl-legend-line' }, legend), det);
  }

  let simSelect = null, simNote = null, groupSel = null;
  function buildSectionControls(s) {
    const id = s.sec.id;
    const stop = (e) => e.stopPropagation();
    if (id === 'controls') {
      const strip = el('div', { class: 'tl-strip tl-controls' });
      strip.appendChild(el('div', { class: 'tl-legend' },
        el('span', { class: 'tl-legend-item' }, kindMark('view'), el('span', { text: 'view only: drawn from the map, the estimate and the Sim, nothing to drag (a recessed background)' })),
        el('span', { class: 'tl-legend-item' }, kindMark('edit'), el('span', { text: 'editing: drag, click and type here to change the map' }))));
      const row = el('div', { class: 'tl-ctl-row' });
      row.appendChild(el('span', { class: 'tl-ctl-group' }, el('b', { text: 'Sections' }),
        el('button', { class: 'btn small', type: 'button', text: 'Collapse all', title: 'fold every section to its bar (the ruler stays)', onclick: () => setAll(true) }),
        el('button', { class: 'btn small', type: 'button', text: 'Open all', title: 'open every section and every group of spawn rows', onclick: () => setAll(false) })));
      row.appendChild(el('span', { class: 'tl-ctl-group', title: 'what the estimate assumes (On screen, Challenge, Composition, Spawned so far, the Actual lanes and the warnings read it): the share of the living crowd the hero kills a second, how long a boss fight and its portal wait last. Empty = the numbers from your runs (the grey ones); ↺ goes back to them' }, el('b', { text: 'Estimate' }), spawnControls(), simLifeBox()));
      simSelect = el('select', { class: 'tl-sim-pick', title: 'the finished Sim whose real numbers the On screen, Challenge and Composition lanes show beside the estimate (the Sim tab runs one); none = the estimate alone' });
      simSelect.appendChild(el('option', { value: '', text: 'none' }));
      simSelect.addEventListener('change', () => pickSim(simSelect.value));
      simNote = el('span', { class: 'muted small tl-sim-note' });
      row.appendChild(el('span', { class: 'tl-ctl-group' }, el('b', { text: 'Sim to show' }), simSelect, simNote));
      strip.appendChild(row);
      s.body.appendChild(strip);
      return;
    }
    if (id === 'onscreen') {
      s.body.appendChild(explainStrip('onscreen', [lg('sw-alive', 'estimate (regular channel)'), lg('sw-hell', 'hell channel'), lg('sw-sim', 'Sim'), lg('sw-capb', 'cap in bodies'), lg('sw-floor', 'floor'), lg('sw-hard', 'hard cap'), lg('sw-full', 'cap full: rows starve')]));
      return;
    }
    if (id === 'challenge') {
      s.ctl.appendChild(miniSelect([{ v: 'seconds', label: 'seconds to clear the screen', help: 'the crowd\'s HP on screen ÷ the hero\'s damage a second' }, { v: 'bars', label: 'health bars lost clearing it', help: '(seconds to clear) × (the crowd\'s bite a second ÷ his effective HP) = HP × ATK of the crowd ÷ (DPS × EHP): the Sim\'s "challenge"' }], prefs.chal, (v) => setPref('chal', v), 'what the lane measures'));
      const box = (k, label, help) => {
        const inp = el('input', { type: 'number', class: 'num tiny', min: 0.1, step: 'any', title: help, 'data-zone': k });
        inp.addEventListener('click', stop);
        inp.addEventListener('keydown', (e) => { e.stopPropagation(); if (e.key === 'Enter') inp.blur(); });
        inp.addEventListener('change', () => {
          const v = Number(inp.value);
          const set = prefs.chal === 'bars' ? 'bars' : 'seconds';
          const z = Object.assign({}, zoneSets[set]);
          if (v > 0) z[k] = v;
          if (z.hard <= z.easy) { inp.value = zoneSets[set][k]; App.toast('The hard limit must be above the easy one'); return; }
          zoneSets[set] = z;
          try { localStorage.setItem(ZONE_KEY, JSON.stringify(zoneSets)); } catch (_) { /* fine */ }
          render();
        });
        return el('label', { class: 'tl-zone', title: help }, label, inp, el('span', { class: 'tl-zone-unit' }));
      };
      s.ctl.appendChild(box('easy', 'easy under', 'under this the lane is green (a page setting, one pair per measure)'));
      s.ctl.appendChild(box('hard', 'hard over', 'over this the lane is red (a page setting, one pair per measure)'));
      s.body.appendChild(explainStrip('challenge', [lg('sw-easy', 'easy'), lg('sw-fair', 'fair'), lg('sw-hardz', 'hard'), lg('sw-chal', 'the estimate'), lg('sw-sim', 'the Sim'), lg('sw-death', 'a Sim death')]));
      return;
    }
    if (id === 'composition') {
      s.ctl.appendChild(miniSelect([{ v: 'alive', label: 'on screen', help: 'shares of the creatures alive' }, { v: 'spawned', label: 'spawned in the past N s', help: 'shares of what spawned in the past N seconds (the "past" box in the top bar)' }], prefs.comp, (v) => setPref('comp', v), 'what the shares are of'));
      s.ctl.appendChild(miniSelect([{ v: 'est', label: 'estimate', help: 'the Spawned so far estimate' }, { v: 'sim', label: 'Sim', help: 'the Sim picked in Ruler and controls (on screen only)' }], prefs.compSrc, (v) => setPref('compSrc', v), 'whose numbers'));
      s.body.appendChild(explainStrip('composition', [lg('sw-comp', 'one colour per creature: hover for the names, the counts and the shares')]));
      return;
    }
    if (id === 'rows') {
      s.ctl.appendChild(el('span', { class: 'muted small', text: 'group' }));
      groupSel = miniSelect(GROUP_MODES, prefs.group, (v) => setPref('group', v), 'how the rows are grouped on this page (the game ignores it)');
      s.ctl.appendChild(groupSel);
      s.ctl.appendChild(el('span', { class: 'muted small', text: 'colour' }));
      s.ctl.appendChild(miniSelect(COLOUR_MODES, prefs.colour, (v) => setPref('colour', v), 'what the bars\' colour says'));
      s.ctl.appendChild(el('button', { class: 'btn small', type: 'button', text: 'Suggest roles', title: 'give every untagged row a role from its keys and its creature (special, elite, once / off the cap = swarm, a ranged creature, a heavy one = tank, else fodder); one undo step; rows with a role keep it', onclick: (e) => { e.stopPropagation(); suggestRoles(); } }));
      s.ctl.appendChild(el('button', { class: 'btn small ghost', type: 'button', text: 'Fold groups', title: 'fold every group of rows to its bar', onclick: (e) => { e.stopPropagation(); foldGroups(true); } }));
      s.ctl.appendChild(el('button', { class: 'btn small ghost', type: 'button', text: 'Open groups', onclick: (e) => { e.stopPropagation(); foldGroups(false); } }));
      const roles = el('div', { class: 'tl-legend-line' }, el('span', { class: 'muted small', text: 'Roles: ' }), TimelineModel.ROLES.map((r) => lg('', r.label, r.help)));
      for (const [k, r] of TimelineModel.ROLES.entries()) roles.querySelectorAll('.lg-sw')[k].style.background = r.color;
      s.body.appendChild(el('div', { class: 'tl-strip tl-rows-legend' }, roles,
        el('div', { class: 'muted small', text: 'On each bar: the creature, how many and how often (≈ per minute for a continuous row: the estimate over its life), its HP and ATK in play at its start, the presence weight, then badges: ★ elite modifier, ◆ special, ⚑ banner, the pattern, hell, the art variant, a wrench for overrides. Yellow ticks: when its creatures come.' })));
      return;
    }
    if (id === 'warnings') {
      s.body.appendChild(el('div', { class: 'tl-strip tl-warn', 'data-warnings': '1' }));
    }
  }

  /** "lifetimes from the Sim": the estimate lets each creature the shown Sim measured live its measured seconds (lane
   *  SPAWN's opts.life) instead of the kill rate (pass 84). */
  let simLifeInput = null;
  function simLifeBox() {
    simLifeInput = el('input', { type: 'checkbox' });
    simLifeInput.checked = !!App.S.useSimLife;
    simLifeInput.addEventListener('change', () => App.setUseSimLife(simLifeInput.checked));
    return el('label', { class: 'tl-check', title: 'ticked: in the estimate each creature the shown Sim measured leaves the crowd after its measured lifetime (life_by in the Sim: seconds from spawn to death), the rest by the kill rate; unticked: every creature by the kill rate. Needs a Sim with lifetimes (pass 84 on)' }, simLifeInput, 'lifetimes from the Sim');
  }

  function foldGroups(on) {
    const rows = App.tl().roster || [];
    const keys = new Set(rows.map((r) => groupOf(r, prefs.group).key));
    for (const k of keys) if (on) secState['group:' + k] = true; else delete secState['group:' + k];
    saveSecState();
    render();
  }

  /** Every untagged row gets TimelineModel.suggestRole's role (one undo step). */
  function suggestRoles() {
    const rows = App.tl().roster || [];
    const todo = rows.map((r, i) => ({ i, role: TimelineModel.roleOf(r) ? '' : TimelineModel.suggestRole(r, App.creature(firstEnemy(r))) })).filter((x) => x.role);
    if (!todo.length) { App.toast('Every row has a role already'); return; }
    App.apply((tl) => { for (const x of todo) tl.roster[x.i].role = x.role; });
    App.toast(`Gave ${todo.length} row${todo.length === 1 ? '' : 's'} a role (Ctrl+Z undoes)`, { undo: true });
  }

  /** The first creature a row names ('' for the roster draw). */
  function firstEnemy(r) {
    if (!r) return '';
    if (Array.isArray(r.enemy)) return String(r.enemy[0] || '');
    return r.enemy === 'roster' ? '' : String(r.enemy || '');
  }
  /** How a row names its creatures, in words: "Skeleton", "Skeleton +2", "the roster draw". */
  function enemyWords(r) {
    if (Array.isArray(r.enemy)) return r.enemy.length > 1 ? `${App.creatureName(r.enemy[0])} +${r.enemy.length - 1}` : App.creatureName(r.enemy[0]);
    if (r.enemy === 'roster') return 'roster draw';
    return App.creatureName(r.enemy);
  }

  /** Each section's bar: collapsed or open, its chevron and words. */
  function syncSections() {
    for (const s of Object.values(sections)) {
      const c = isCollapsed(s.sec.id);
      s.root.classList.toggle('collapsed', c);
      s.head.setAttribute('aria-expanded', String(!c));
      s.bar.querySelector('.tl-chev').textContent = c ? '▸' : '▾';
      s.sum.textContent = c ? sectionSummary(s.sec.id) : '';
      s.hint.textContent = c ? 'collapsed: click to open' : '';
      s.head.title = c ? `${s.sec.name} is collapsed: click to open it` : `${s.sec.name}: click the bar to collapse it`;
    }
    if (simNote) simNote.textContent = simOv ? simOv.note : (simList.length ? '' : 'no finished Sim of this map yet');
  }

  /** A collapsed section's summary: what it holds, in a line. */
  function sectionSummary(id) {
    const tl = App.tl();
    const v = view;
    try {
      if (id === 'controls') return `the ruler stays · kill rate from ${App.turnoverSource()} · Sim: ${simOv ? simOv.label : 'none'}`;
      if (id === 'onscreen' && v) {
        let pk = 0;
        for (let j = 1; j < v.n; j++) if (v.alive[j] > v.alive[pk]) pk = j;
        const runs = fullRuns(v);
        return `peak ${Math.round(v.alive[pk])} alive at ${fmtT(v.t[pk])} · cap full ${runs.length} time${runs.length === 1 ? '' : 's'}${runs.length ? ` (first ${fmtT(runs[0].a)})` : ''}`;
      }
      if (id === 'challenge' && v) {
        let pk = -1;
        for (let j = 0; j < v.n; j++) if (v.clear[j] != null && (pk < 0 || v.clear[j] > v.clear[pk])) pk = j;
        const deaths = simOv ? simOv.deaths.length : 0;
        return pk >= 0 ? `hardest: ${fmtN(v.clear[pk], 1)} s to clear the screen at ${fmtT(v.t[pk])} (${TimelineModel.zoneOf(v.clear[pk], zoneSets.seconds)})${simOv ? ` · ${deaths} Sim death${deaths === 1 ? '' : 's'}` : ''}` : 'nothing alive';
      }
      if (id === 'composition' && v) {
        const tot = {};
        let all = 0;
        for (const [cid, arr] of Object.entries(v.ser.id)) { let s2 = 0; for (let j = 0; j < v.n; j++) s2 += arr[j]; tot[cid] = s2; all += s2; }
        const top = Object.entries(tot).sort((a, b) => b[1] - a[1]).slice(0, 3);
        return top.length ? `most on screen over the run: ${top.map(([cid, n2]) => `${App.creatureName(cid)} ${Math.round(all > 0 ? (n2 / all) * 100 : 0)}%`).join(', ')}` : 'nobody';
      }
      if (id === 'spawned' && lastSpawn) { const SE = App.stageEnd(App.viewStage() == null ? 0 : App.viewStage()); const p = Model.estimateAt(lastSpawn.est, SE, true); return `≈${fmtCount(p ? p.all : 0)} spawned by ${fmtT(SE)}`; }
      if (id === 'rows') {
        const rows = tl.roster || [];
        const n = (p) => rows.filter((r) => TimelineModel.paceOf(r) === p).length;
        return `${rows.length} rows: ${n('continuous')} continuous, ${n('waves')} waves, ${n('once')} once · ${rows.filter((r) => r.stats && Object.keys(r.stats).length).length} with overrides${(tl.waves || []).length ? ` · ${(tl.waves || []).length} old wave blocks` : ''}`;
      }
      if (id === 'events') {
        const evs = tl.events || [];
        const sp = tl.specials || {};
        let offers = 0;
        for (let st = 0; st < App.stages() && (tl.path_times || []).length; st++) offers += ((tl.path_times[Math.min(st, tl.path_times.length - 1)]) || []).length;
        return `${evs.filter((e) => e.type === 'boss').length} bosses · ${evs.filter((e) => e.type === 'elite_boss').length} Elites${evs.filter((e) => !['boss', 'elite_boss'].includes(e.type)).length ? ` · ${evs.filter((e) => !['boss', 'elite_boss'].includes(e.type)).length} old events` : ''} · specials ${sp.pool ? `from ${fmtT(sp.from)}` : 'none'} · ${offers} mutation offers`;
      }
      if (id === 'curves') {
        const fc = Array.isArray(tl.floor_curve) ? tl.floor_curve : [];
        return `cap ${App.capAt(0)} → ${App.capAt(App.runEnd() - 1)} · floor ${fc.length ? `${fc.length} points` : 'none'} · HP ×${fmtN(App.hpTimeMult(0), 2)} → ×${fmtN(App.hpTimeMult(App.runEnd()), 2)} · ATK ×${fmtN(App.dmgTimeMult(0), 2)} → ×${fmtN(App.dmgTimeMult(App.runEnd()), 2)}`;
      }
      if (id === 'warnings') { const ws = warningsOf(); return ws.length ? `${ws.length} found: ${ws.slice(0, 2).map((x) => x.short || x.text).join(' · ')}${ws.length > 2 ? ' …' : ''}` : 'nothing found'; }
    } catch (e) { console.error('section summary', id, e); }
    return '';
  }

  // ------------------------------------------------------------------ the inspector's fold (pass 84)

  const INSP_KEY = '88fits-editor-insp-folded';
  function wireInspectorFold() {
    const panel = document.getElementById('tab-timeline');
    const insp = document.getElementById('inspector');
    if (!panel || !insp || document.getElementById('insp-fold')) return;
    const btn = el('button', { id: 'insp-fold', class: 'insp-fold', type: 'button', text: '⇥', title: 'fold the inspector to a slim bar (the timeline gets the room)' });
    const barEl = el('button', { id: 'insp-folded-bar', class: 'insp-folded-bar', type: 'button', title: 'the inspector is folded: click to open it' },
      el('span', { class: 'ifb-chev', text: '◂' }), el('span', { class: 'ifb-text', text: 'Inspector · folded: click to open' }));
    const set = (on) => {
      panel.classList.toggle('insp-folded', on);
      try { localStorage.setItem(INSP_KEY, on ? '1' : '0'); } catch (_) { /* fine */ }
      if (App.S.map) render();
    };
    btn.addEventListener('click', () => set(true));
    barEl.addEventListener('click', () => set(false));
    panel.appendChild(btn);
    panel.appendChild(barEl);
    let on = false;
    try { on = localStorage.getItem(INSP_KEY) === '1'; } catch (_) { /* open */ }
    panel.classList.toggle('insp-folded', on);
  }

  // ------------------------------------------------------------------ the Sim overlay (pass 84)

  // The newest finished Sim of this map (or the one picked) as the view lanes' second opinion, from lane SIMVIEW's route
  // GET /api/sim/overlay?map=<map>&id=<sim> (every series by the map clock: index c = run second c; boss fights and the
  // portal wait left out, their seconds in `bosses`): alive (both channels, the regular and the hell apart), load and the
  // cap, cap_full, starving rows, threat, the hero's full DPS, effective HP and power, challenge, who was alive, its
  // deaths and each creature's lifetime. Its keep_up (seconds of his own damage to clear the crowd, per play second) comes
  // from the result itself for the Challenge lane's seconds. An older server without the route: the result alone.
  // pass 87 (lane STOOLS): each tab remembers its own Sim (a stage tab: by default the newest Sim of that stage)
  const SIM_KEY = (map) => `88fits-editor-sim-${map || ''}${App.viewStage() == null ? '' : '-s' + (App.viewStage() + 1)}`;
  let simOv = null, simList = [], simFor = null, simBusy = false;
  async function loadSimList(force) {
    const mapId = App.S.mapId || '';
    const forKey = mapId + '|' + (App.viewStage() == null ? 'all' : App.viewStage());
    if (!force && simFor === forKey) return;
    simFor = forKey;
    simList = []; simOv = null;
    try {
      const r = await fetch('/api/sim/history', { cache: 'no-store' });
      const h = r.ok ? await r.json() : {};
      simList = (h.sims || []).filter((x) => x && x.has_result && !x.synthetic && !x.partial && (((x.settings || {}).map) || 'red_canyon') === mapId);
    } catch (_) { simList = []; }
    if (simSelect) {
      clear(simSelect);
      simSelect.appendChild(el('option', { value: '', text: 'none (the estimate alone)' }));
      for (const x of simList) simSelect.appendChild(el('option', { value: x.id, text: `${x.id} · ${x.hero_name || ''} · ${(x.settings || {}).stage ? 'stage ' + x.settings.stage : 'all stages (before pass 87)'} · ${x.players_done || '?'} runs · ${String(x.started || '').replace('T', ' ').slice(0, 16)}` }));
    }
    let want = '';
    try { want = localStorage.getItem(SIM_KEY(mapId)) || ''; } catch (_) { /* the newest */ }
    // a stage tab's default: the newest Sim of that stage, else the newest
    const vs = App.viewStage();
    const first = (vs == null ? null : simList.find((x) => Number((x.settings || {}).stage) === vs + 1)) || simList[0] || {};
    const pick = want === '-' ? '' : ((simList.find((x) => x.id === want) || first).id || '');
    if (simSelect) simSelect.value = pick;
    if (pick) await pickSim(pick, true); else render();
  }

  async function pickSim(id, quiet) {
    try { localStorage.setItem(SIM_KEY(App.S.mapId), id || '-'); } catch (_) { /* fine */ }
    if (!id) { simOv = null; App.setSimLife(null); render(); return; }
    if (simBusy) return;
    simBusy = true;
    let ov = null;
    try {
      const r = await fetch(`/api/sim/overlay?map=${encodeURIComponent(App.S.mapId)}&id=${encodeURIComponent(id)}&top=14`, { cache: 'no-store' });
      const d = r.ok ? await r.json() : null;
      if (d && d.ok && d.overlay) ov = fromOverlay(d, id);
      else if (d && d.reason && !quiet) App.toast(`The Sim's overlay: ${d.reason}`);
    } catch (_) { /* the result alone */ }
    let res = null;
    try { const r = await fetch(`/api/sim/result/${encodeURIComponent(id)}`, { cache: 'no-store' }); if (r.ok) res = await r.json(); } catch (_) { /* no keep_up */ }
    if (!ov && res) ov = fromResult(res, simList.find((x) => x.id === id) || { id });
    if (ov && res) addKeepUp(ov, res);
    simOv = ov;
    if (!simOv && !quiet) App.toast(`The Sim ${id} has no series to show`);
    App.setSimLife(simOv && simOv.life ? simOv.life : null);
    simBusy = false;
    render();
  }

  /** The overlay route's answer, every series by the clock second. */
  function fromOverlay(d, id) {
    const o = d.overlay, sim = d.sim || {};
    const se = o.series || {};
    const pick = (k, f) => { const x = se[k]; if (!x) return null; for (const g of [f, 'mean', 'median']) if (Array.isArray(x[g])) return x[g]; return null; };
    const C = Number(o.C) || (pick('alive', 'mean') || []).length;
    const clock = Array.from({ length: C + 1 }, (_, c) => c);
    const aliveBy = {};
    const ab = o.alive_by && o.alive_by.mean ? o.alive_by.mean : {};
    for (const [cid, arr] of Object.entries(ab)) if (Array.isArray(arr)) aliveBy[cid] = arr;
    const life = {};
    for (const [cid, L] of Object.entries(o.life_by || {})) if (L && Number(L.mean_s) > 0) life[cid] = Number(L.mean_s);
    // the Sim's starving rows by this map's roster index (its `rows` say which row each key was, as simulated)
    const rowsSim = Array.isArray(o.rows) ? o.rows : [];
    const starving = {};
    for (const [key, arr] of Object.entries((o.starving || {}).share || {})) {
      const rr = rowsSim.find((x) => x.key === key);
      starving[rr && rr.k != null ? `roster:${rr.k}` : key] = arr;
    }
    const runs = sim.ok_players || sim.players || 0;
    return {
      id, label: `${id} (${runs} run${runs === 1 ? '' : 's'})`,
      note: `${sim.hero_name || sim.hero || ''} · ${runs} runs${sim.board_words ? ` · board ${sim.board_words}` : ''} · ${String(sim.started || '').replace('T', ' ').slice(0, 16)}${sim.stale ? ' · the map changed since' : ''}`,
      stale: !!sim.stale, clock, n: C + 1, has: o.has || [],
      alive: pick('alive', 'mean'), aliveReg: pick('alive_reg', 'mean'), aliveHell: pick('alive_hell', 'mean'), load: pick('load', 'mean'), cap: pick('cap', 'mean'),
      capFull: pick('cap_full', 'mean'), threat: pick('threat', 'mean'), power: pick('power', 'mean'), dps: pick('hero_dps', 'mean'), ehp: pick('hero_ehp', 'mean'),
      level: pick('level', 'mean'), challenge: pick('challenge', 'median'), keep: null, playing: o.playing || null,
      deaths: (o.deaths || []).map((x) => Number(x.clock) || 0), aliveBy, life, starving, names: o.names || {}, rules: o.rules || {},
    };
  }

  /** A Sim from before the route (its result.json): the play-second series placed on the clock. */
  function fromResult(res, entry) {
    const s = res.series || {};
    const pick = (k, f) => { const x = s[k]; if (!x) return null; if (Array.isArray(x)) return x; for (const g of [f, 'mean', 'median']) if (x && Array.isArray(x[g])) return x[g]; return null; };
    const clock = pick('clock', 'median') || res.t || [];
    const n = clock.length;
    if (!n) return null;
    const end = Math.ceil(Math.max(...clock.map((c) => Number(c) || 0))) + 1;
    const byClock = (arr) => {
      if (!arr) return null;
      const out = new Array(end + 1).fill(null);
      for (let i = 0; i < n; i++) { const c = Math.round(Number(clock[i]) || 0); const v = arr[i]; if (v != null && isFinite(v)) out[c] = Number(v); }
      return out;
    };
    const ab = ((res.breakdowns || {}).alive_by || {}).mean || {};
    const aliveBy = {};
    for (const [cid, arr] of Object.entries(ab)) if (Array.isArray(arr)) aliveBy[cid] = byClock(arr);
    const meta = res.meta || {};
    const runs = meta.players_done || entry.players_done || 0;
    return {
      id: entry.id || meta.id || '', label: `${entry.id || meta.id || 'sim'} (${runs} run${runs === 1 ? '' : 's'})`,
      note: `${entry.hero_name || meta.hero_name || ''} · ${runs} runs · ${String(meta.started || entry.started || '').replace('T', ' ').slice(0, 16)} · an older Sim (alive, cap, power only)`,
      clock: Array.from({ length: end + 1 }, (_, c) => c), n: end + 1, has: ['alive', 'cap', 'power'],
      alive: byClock(pick('alive', 'mean')), aliveReg: null, aliveHell: null, load: null, cap: byClock(pick('cap', 'mean')), capFull: null, threat: null,
      power: byClock(pick('power', 'mean')), dps: null, ehp: null, level: byClock(pick('level', 'mean')), challenge: null, keep: null,
      deaths: ((res.markers || {}).deaths || []).map((pt) => Number(clock[Math.max(0, Math.min(n - 1, Math.round(Number(pt) || 0)))]) || 0),
      aliveBy, life: null, starving: {}, names: res.names || {}, rules: {},
    };
  }

  /** The Sim's keep_up (seconds of his own damage over 5 s to clear the crowd, the boss left out; the middle run) on the
   *  clock, from its result. */
  function addKeepUp(ov, res) {
    const s = res.series || {};
    const clock = s.clock && Array.isArray(s.clock.median) ? s.clock.median : null;
    const ku = s.keep_up && Array.isArray(s.keep_up.median) ? s.keep_up.median : null;
    if (!clock || !ku) return;
    const out = new Array(ov.n).fill(null);
    const phase = s.phase && Array.isArray(s.phase.mean) ? s.phase.mean : null;
    for (let i = 0; i < clock.length && i < ku.length; i++) {
      if (phase && phase[i] > 0.5) continue;
      const c = Math.round(Number(clock[i]) || 0);
      if (c >= 0 && c < out.length && ku[i] != null && isFinite(ku[i])) out[c] = Number(ku[i]);
    }
    ov.keep = out;
    // an older Sim has no full DPS: its real damage a second (5 s) stands in for the hero's damage
    const dm = s.dps && Array.isArray(s.dps.mean) ? s.dps.mean : null;
    if (dm && !ov.dps) {
      const d2 = new Array(ov.n).fill(null);
      for (let i = 0; i < clock.length && i < dm.length; i++) {
        if (phase && phase[i] > 0.5) continue;
        const c = Math.round(Number(clock[i]) || 0);
        if (c >= 0 && c < d2.length && dm[i] != null && isFinite(dm[i])) d2[c] = Number(dm[i]);
      }
      ov.dpsReal = d2;
    }
  }

  /** The Sim's value of a clock series at run second t (the nearest second that has one, within 3). */
  function simAt(arr, t) {
    if (!arr) return null;
    const k = Math.round(t);
    for (let d = 0; d <= 3; d++) {
      if (k - d >= 0 && k - d < arr.length && arr[k - d] != null) return arr[k - d];
      if (k + d < arr.length && arr[k + d] != null) return arr[k + d];
    }
    return null;
  }

  // ------------------------------------------------------------------ the view lanes' numbers (pass 84)

  /** The view lanes' numbers for an estimate, kept while nothing they read changes. */
  let viewCache = { est: null, key: '', v: null };
  function viewOf(res) {
    const est = res.est;
    const key = [App.S.level, simOv ? simOv.id : '', App.S.enemiesRev].join('|');
    if (viewCache.est === est && viewCache.key === key && viewCache.v) return viewCache.v;
    let v = null;
    try { v = computeView(est); } catch (e) { console.error('the view lanes could not be worked out', e); }
    viewCache = { est, key, v };
    warnCache = null;
    return v;
  }

  /** The source key's creature: a row's (or a list row's when the estimate names it: 'roster:3:skeleton'), a wave
   *  alternative's; '' when the source brings several (the estimate files those under their creatures). */
  function srcCreatureOf(k) {
    const tl = App.tl();
    const parts = k.split(':');
    if (parts[0] === 'roster') {
      const r = (tl.roster || [])[Number(parts[1])];
      if (!r) return '';
      if (parts.length > 2) return parts.slice(2).join(':');
      return typeof r.enemy === 'string' && r.enemy !== 'roster' ? r.enemy : '';
    }
    if (parts[0] === 'wave') {
      const w = (tl.waves || [])[Number(parts[1])];
      const a = w ? App.waveAlts(w)[Number(parts[2])] : null;
      return a ? String(a.alt.enemy || '') : '';
    }
    return '';
  }

  function computeView(est) {
    const tl = App.tl();
    const rows = tl.roster || [], waves = tl.waves || [];
    const ser = TimelineModel.aliveSeries(est, srcCreatureOf, App.stageAt);
    const n = ser.n;
    const isHellKey = (k) => {
      const p = k.split(':');
      if (p[0] === 'roster') { const r = rows[Number(p[1])]; return !!r && r.channel === 'hell'; }
      if (p[0] === 'wave') { const w = waves[Number(p[1])]; return !!w && w.channel === 'hell'; }
      return false;
    };
    const shareOf = (id) => { const c = App.creature(id); return c && c.cap_share != null && c.cap_share !== '' ? Number(c.cap_share) : 1; };
    const dflt = U.isObj(tl.special_defaults) ? tl.special_defaults : {};
    const runEnd = App.runEnd();
    const ews = Math.max(1, Number(tl.endless_wave_seconds) || 60);
    const cache = new Map();
    function numbersOf(key, t) {
      const parts = key.split(':');
      let c = null, stats = null, t0 = null;
      if (parts[0] === 'roster') { const r = rows[Number(parts[1])]; if (r) { c = App.creature(ser.keyId[key]); stats = r.stats; t0 = Number(r.t) || 0; } }
      else if (parts[0] === 'wave') { const w = waves[Number(parts[1])]; const a = w ? App.waveAlts(w)[Number(parts[2])] : null; if (a) { c = App.creature(a.alt.enemy); stats = a.alt.stats; t0 = Number(w.t) || 0; } }
      else c = App.creature(parts.slice(1).join(':'));
      if (!c) return null;
      // a row's numbers are fixed from its start: only the stage (and an endless wave) moves them; the others (swarms,
      // Elites, specials) take the curves at the second they come: read every 10 s
      const stg = App.stageAt(t);
      const enW = t >= runEnd ? Math.floor((t - runEnd) / ews) : -1;
      const ck = `${key}|${stg}|${enW}|${t0 == null ? Math.floor(t / 10) : ''}`;
      if (cache.has(ck)) return cache.get(ck);
      const st = U.isObj(stats) ? stats : {};
      const at = App.creatureAt(c, st, t, t0 == null ? t : t0);
      const vs = Model.varianceSpecial(c, st, dflt);
      const x = { hp: at.hp, atk: at.atk, bite: Number(st.contact_cd != null ? st.contact_cd : (c.contact_cd != null ? c.contact_cd : 0.6)) || 0.6, boss: at.arch === 'boss', spHp: vs.chance > 0 ? Model.specialValue(vs.sp, dflt, 'hp') : 1 };
      cache.set(ck, x);
      return x;
    }
    // pass 87: every stage is a fresh run, so the typical hero starts at power 1 at each window's start (his power by
    // the seconds he has played, on the first stage's marks)
    const SL = App.stageLen(0);
    const marks = typeof PowerModel !== 'undefined' ? PowerModel.TYPICAL.map((m, k) => ({ t: k * SL, power: m.power })) : [{ t: 0, power: 1 }];
    const played = (t) => Math.max(0, t - App.stageStart(Math.min(App.stageAt(t), App.stages() - 1)));
    const baseDps = typeof PowerModel !== 'undefined' ? PowerModel.BASE_DPS : 20.4;
    const baseEhp = typeof PowerModel !== 'undefined' ? PowerModel.BASE_EHP : 100;
    const v = { n, ser, t: ser.t, alive: ser.alive, reg: new Float64Array(n), hell: new Float64Array(n), cap: new Float64Array(n), capB: new Float64Array(n), full: new Uint8Array(n),
      hp: new Float64Array(n), bite: new Float64Array(n), threat: new Float64Array(n), dps: new Float64Array(n), dpsSim: new Uint8Array(n), ehp: new Float64Array(n), ehpSim: new Uint8Array(n), clear: new Array(n).fill(null), bars: new Array(n).fill(null), crowd: new Array(n) };
    for (let j = 0; j < n; j++) {
      const t = ser.t[j];
      const L = TimelineModel.loadAt(ser, j, shareOf, isHellKey);
      const pt = est.points[j] || {};
      // lane SPAWN's estimate carries the director's cap (a boss fight's share in it), the regular load and the share of
      // that second's checks that found no room (pass 84); an older estimate: the curve and the sources' load
      const cap = pt.cap != null ? Number(pt.cap) : App.capAt(t);
      const load = pt.load != null ? Number(pt.load) : L.load;
      v.reg[j] = L.bodies; v.hell[j] = L.hellBodies; v.cap[j] = cap;
      v.capB[j] = TimelineModel.capBodies(cap, load, L.bodies, 1);
      v.full[j] = pt.full != null ? (Number(pt.full) >= 0.5 ? 1 : 0) : (cap > 0 && load >= cap * TimelineModel.FULL_AT ? 1 : 0);
      const cr = TimelineModel.crowdAt(ser, j, numbersOf);
      v.crowd[j] = cr;
      v.hp[j] = cr.hp; v.bite[j] = cr.bite; v.threat[j] = cr.threat;
      // the Sim's hero: his full DPS and effective HP (pass 84 Sims), else his real damage a second (an older Sim); else
      // a typical hero from the power curve
      let sd = simOv ? simAt(simOv.dps, t) : null;
      let dsrc = sd != null && sd >= 1 ? 1 : 0;
      if (!dsrc && simOv) { sd = simAt(simOv.dpsReal, t); dsrc = sd != null && sd >= 1 ? 2 : 0; }
      const se = simOv ? simAt(simOv.ehp, t) : null;
      const typ = TimelineModel.typicalHero(played(t), marks, baseDps, baseEhp);
      const dps = dsrc ? sd : typ.dps;
      const ehp = se != null && se >= 1 ? se : typ.ehp;
      v.dps[j] = dps; v.dpsSim[j] = dsrc; v.ehp[j] = ehp; v.ehpSim[j] = se != null && se >= 1 ? 1 : 0;
      v.clear[j] = dps > 0 && cr.n >= 0.5 ? cr.hp / dps : null;
      v.bars[j] = dps > 0 && ehp > 0 && cr.n >= 0.5 ? cr.threat / (dps * ehp) : null;
    }
    v.rowsInfo = rows.map((r, i) => ({ key: `roster:${i}`, drawn: Model.rowDrawn(r) && r.channel !== 'hell' && TimelineModel.paceOf(r) === 'continuous' || (Model.rowDrawn(r) && r.channel !== 'hell' && !!r.trickle),
      open: (t) => t >= (Number(r.t) || 0) && t < (r.until == null || r.until === '' ? Infinity : Number(r.until)), weight: (t) => App.rowWeight(r, t) }));
    v.starving = (j) => TimelineModel.starvingAt(est, ser, j, v.rowsInfo, (jj) => !!v.full[jj]);
    return v;
  }

  /** The stretches where the cap is full: [{a, b, j0, j1}] in run seconds. */
  function fullRuns(v) {
    const out = [];
    let j0 = -1;
    for (let j = 0; j <= v.n; j++) {
      const on = j < v.n && v.full[j];
      if (on && j0 < 0) j0 = j;
      if (!on && j0 >= 0) { out.push({ a: v.t[j0], b: v.t[Math.min(j, v.n - 1)], j0, j1: j - 1 }); j0 = -1; }
    }
    return out;
  }

  /** The source keys' words for a card: "Skeleton (row r5)". */
  function srcWords(key) {
    const tl = App.tl();
    const p = key.split(':');
    if (p[0] === 'roster') { const r = (tl.roster || [])[Number(p[1])]; return r ? `${r.name ? r.name + ': ' : ''}${enemyWords(r)} (row ${r.id || Number(p[1]) + 1})` : key; }
    if (p[0] === 'wave') { const w = (tl.waves || [])[Number(p[1])]; return w ? `${w.name || w.id || 'wave'}` : key; }
    return App.creatureName(p.slice(1).join(':'));
  }

  // ------------------------------------------------------------------ On screen (pass 84)

  const ALIVE_H = 156;
  function renderAlive(w) {
    const s = clear(lanes.alive.svg);
    setHeight('alive', ALIVE_H);
    stageShade(s, ALIVE_H);
    const v = view;
    if (!v || !v.n) { s.appendChild(svg('text', { x: 8, y: 24, class: 'hint-text', text: 'no estimate yet' })); return; }
    const tl = App.tl();
    const hard = Number(tl.hard_cap) || 0;
    const fc = Array.isArray(tl.floor_curve) ? tl.floor_curve.filter((p) => Array.isArray(p)).slice().sort((a, b) => a[0] - b[0]) : [];
    const floorAt = (t) => (fc.length ? Model.samplePoints(fc, t) : 0);
    let maxV = 10;
    for (let j = 0; j < v.n; j++) { maxV = Math.max(maxV, v.alive[j]); if (isFinite(v.capB[j])) maxV = Math.max(maxV, Math.min(v.capB[j], hard || Infinity)); }
    for (const p of fc) maxV = Math.max(maxV, Number(p[1]) || 0);
    if (simOv && simOv.alive) for (const a of simOv.alive) if (a != null) maxV = Math.max(maxV, a);
    if (hard > 0) maxV = Math.min(maxV, hard * 1.05);
    maxV *= 1.1;
    const top = 12, bottom = ALIVE_H - 8;
    const y = (val) => bottom - (Math.min(Math.max(0, val), maxV) / maxV) * (bottom - top);
    const g = svg('g', { class: 'alive-lane', 'data-hover': 'alive' });
    g.appendChild(svg('rect', { x: 0, y: 0, width: w, height: ALIVE_H, class: 'sp-hit' }));
    // red where the cap is full (rows starve there)
    for (const r of fullRuns(v)) g.appendChild(svg('rect', { x: x(r.a), y: top - 4, width: Math.max(2, x(r.b) - x(r.a)), height: bottom - top + 4, class: 'full-band' }));
    const gstep = countStep(maxV);
    for (let val = gstep; val < maxV; val += gstep) {
      g.appendChild(svg('line', { x1: 0, x2: w, y1: y(val), y2: y(val), class: 'grid' }));
      g.appendChild(svg('text', { x: 4, y: y(val) - 2, class: 'grid-text', text: fmtCount(val) }));
    }
    if (hard > 0 && hard <= maxV) {
      g.appendChild(svg('line', { x1: 0, x2: w, y1: y(hard), y2: y(hard), class: 'hard-cap' }));
      g.appendChild(svg('text', { x: 4, y: y(hard) - 3, class: 'hard-cap-text', text: `hard cap ${hard} bodies` }));
    }
    // the estimate: the regular channel's bodies, the hell channel's on top
    const xs = Array.from(v.t, (t) => x(t));
    const regUp = xs.map((px, j) => `${px},${y(v.reg[j])}`);
    const base = xs.map((px) => `${px},${bottom}`).reverse();
    g.appendChild(svg('polygon', { points: regUp.concat(base).join(' '), class: 'alive-area' }));
    if (v.hell.some((h) => h > 0.05)) {
      const hellUp = xs.map((px, j) => `${px},${y(v.reg[j] + v.hell[j])}`);
      g.appendChild(svg('polygon', { points: hellUp.concat(regUp.slice().reverse()).join(' '), class: 'alive-hell' }));
    }
    g.appendChild(svg('polyline', { points: xs.map((px, j) => `${px},${y(v.alive[j])}`).join(' '), class: 'alive-line' }));
    // the cap in bodies at the crowd's mix
    g.appendChild(svg('polyline', { points: xs.map((px, j) => `${px},${y(isFinite(v.capB[j]) ? v.capB[j] : maxV)}`).join(' '), class: 'capb-line' }));
    // the floor
    if (fc.length) {
      let pts = '';
      for (let px = 0; px <= x(App.viewEnd()); px += 3) pts += `${px},${y(floorAt(tAtPx(px)))} `;
      g.appendChild(svg('polyline', { points: pts, class: 'floor-line' }));
    }
    // the Sim's real count
    if (simOv && simOv.alive) {
      const pts = [];
      for (let i = 0; i < simOv.clock.length; i++) if (simOv.alive[i] != null) pts.push(`${x(simOv.clock[i])},${y(simOv.alive[i])}`);
      g.appendChild(svg('polyline', { points: pts.join(' '), class: 'sim-line' }));
    }
    hovers.alive = (t) => aliveCard(t);
    s.appendChild(g);
    let pk = 0;
    for (let j = 1; j < v.n; j++) if (v.alive[j] > v.alive[pk]) pk = j;
    lanes.alive.label.querySelector('.lane-sub').textContent = `peak ${Math.round(v.alive[pk])} at ${fmtT(v.t[pk])}${simOv ? ' · Sim dashed' : ''}`;
  }

  function aliveCard(t) {
    const v = view;
    if (!v) return null;
    const j = TimelineModel.indexAt(v.ser, t);
    if (j < 0) return null;
    const tl = App.tl();
    const box = el('div', { class: 'view-card' });
    box.appendChild(cardHead('On screen', v.t[j], 'creatures alive (bodies), the estimate'));
    box.appendChild(el('div', { class: 'vc-big' }, el('b', { text: fmtCount(v.alive[j]) }), ` alive${v.hell[j] > 0.5 ? ` (${fmtCount(v.reg[j])} regular, ${fmtCount(v.hell[j])} hell)` : ''}`,
      simOv && simAt(simOv.alive, v.t[j]) != null ? el('span', { class: 'muted' }, ` · the Sim: ${fmtCount(simAt(simOv.alive, v.t[j]))}${simOv.capFull && simAt(simOv.capFull, v.t[j]) > 0.05 ? `, its cap full ${Math.round(simAt(simOv.capFull, v.t[j]) * 100)}% of the second` : ''}`) : null));
    const fc = Array.isArray(tl.floor_curve) && tl.floor_curve.length ? Model.samplePoints(tl.floor_curve.slice().sort((a, b) => a[0] - b[0]), v.t[j]) : null;
    box.appendChild(el('div', { class: 'hc-line' }, `cap ${v.cap[j]} load units ≈ `, el('b', { text: `${fmtCount(v.capB[j])} bodies` }), ' at this mix', fc != null ? ` · floor ${Math.round(fc)}` : ' · no floor'));
    if (v.full[j]) {
      const st = v.starving(j);
      box.appendChild(el('div', { class: 'hc-line bad-line' }, el('b', { text: 'The cap is full here: ' }), st.length ? `waiting for room: ${st.slice(0, 6).map(srcWords).join(', ')}${st.length > 6 ? ` and ${st.length - 6} more` : ''}` : 'every row open now still came in the past 5 s'));
    }
    // the Sim's own starving rows at that second (SIMVIEW's starving shares, by this map's roster index)
    if (simOv && simOv.starving) {
      const sv = Object.keys(simOv.starving).filter((k) => (simAt(simOv.starving[k], v.t[j]) || 0) >= TimelineModel.STARVE_SHARE);
      if (sv.length) box.appendChild(el('div', { class: 'hc-line muted' }, 'In the Sim, waiting for room: ', sv.slice(0, 5).map((k) => (k.startsWith('roster:') ? srcWords(k) : k)).join(', '), sv.length > 5 ? ` and ${sv.length - 5} more` : ''));
    }
    const comp = TimelineModel.compositionAt(v.ser, j).slice(0, 6);
    if (comp.length) {
      const grid = el('div', { class: 'vc-grid' });
      for (const cpt of comp) grid.appendChild(el('div', { class: 'vc-r' }, el('i', { class: 'vc-sw', style: `background:${App.creatureColor(cpt.id)}` }), el('span', { text: App.creatureName(cpt.id) }), el('b', { text: fmtCount(cpt.n) }), el('span', { class: 'muted', text: `${Math.round(cpt.share * 100)}%` })));
      box.appendChild(grid);
    }
    box.appendChild(el('div', { class: 'sp-note', text: `An estimate: the director's rules second by second, the hero killing ${App.turnoverSource() === 'your number' ? 'your' : 'the'} kill rate's share of the crowd each second (Ruler and controls). The cap counts load units (cap_share), so it is shown as the bodies it holds at the crowd's mix.` }));
    return box;
  }

  // ------------------------------------------------------------------ Challenge (pass 84)

  const CH_H = 132;
  /** The measure shown: {key 'seconds'|'bars', est (the view's array), sim (the Sim's clock array), unit, words}. */
  function chalMeasure() {
    const bars = prefs.chal === 'bars';
    const v = view;
    return { key: bars ? 'bars' : 'seconds', est: v ? (bars ? v.bars : v.clear) : [], sim: simOv ? (bars ? simOv.challenge : simOv.keep) : null,
      unit: bars ? '' : ' s', fmt: (val) => (bars ? fmtN(val, 2) : `${fmtN(val, 1)} s`), words: bars ? 'health bars lost clearing the screen' : 'seconds to clear the screen' };
  }

  function renderChallenge(w) {
    const s = clear(lanes.challenge.svg);
    setHeight('challenge', CH_H);
    const v = view;
    syncZoneBoxes();
    if (!v || !v.n) return;
    const m = chalMeasure();
    const zones = zonesNow();
    let mx = zones.hard * 1.5;
    for (let j = 0; j < v.n; j++) if (m.est[j] != null) mx = Math.max(mx, m.est[j]);
    if (m.sim) for (const k of m.sim) if (k != null) mx = Math.max(mx, k);
    const maxV = Math.min(mx, zones.hard * 3) * 1.08;
    const top = 12, bottom = CH_H - 10;
    const y = (val) => bottom - (Math.min(Math.max(0, val), maxV) / maxV) * (bottom - top);
    const g = svg('g', { class: 'challenge', 'data-hover': 'challenge' });
    // the zones, full width, then the stages over them
    g.appendChild(svg('rect', { x: 0, y: y(zones.easy), width: w, height: bottom - y(zones.easy), class: 'zone-easy' }));
    g.appendChild(svg('rect', { x: 0, y: y(zones.hard), width: w, height: y(zones.easy) - y(zones.hard), class: 'zone-fair' }));
    g.appendChild(svg('rect', { x: 0, y: top, width: w, height: Math.max(0, y(zones.hard) - top), class: 'zone-hard' }));
    s.appendChild(g);
    stageShade(g, CH_H);
    g.appendChild(svg('rect', { x: 0, y: 0, width: w, height: CH_H, class: 'sp-hit' }));
    for (const [val, word] of [[zones.easy, `easy under ${m.fmt(zones.easy)}`], [zones.hard, `hard over ${m.fmt(zones.hard)}`]]) {
      g.appendChild(svg('line', { x1: 0, x2: w, y1: y(val), y2: y(val), class: 'zone-line' }));
      g.appendChild(svg('text', { x: 4, y: y(val) - 3, class: 'grid-text', text: word }));
    }
    // the estimate, ▲ with its number where it runs off the top
    let pts = [], clipped = 0;
    const flush = () => { if (pts.length > 1) g.appendChild(svg('polyline', { points: pts.join(' '), class: 'chal-line' })); pts = []; };
    for (let j = 0; j < v.n; j++) {
      const c = m.est[j];
      if (c == null) { flush(); continue; }
      pts.push(`${x(v.t[j])},${y(c)}`);
      if (c > maxV && (j === 0 || !(m.est[j - 1] > maxV)) && clipped < 40) { clipped++; g.appendChild(svg('text', { x: Math.min(x(v.t[j]) + 2, w - 60), y: top + 9, class: 'act-clip hp', text: `▲ ${m.fmt(c)}` })); }
    }
    flush();
    if (m.sim) {
      let sp = [];
      const flushS = () => { if (sp.length > 1) g.appendChild(svg('polyline', { points: sp.join(' '), class: 'sim-line' })); sp = []; };
      for (let c = 0; c < m.sim.length; c++) { if (m.sim[c] == null) { flushS(); continue; } sp.push(`${x(c)},${y(m.sim[c])}`); }
      flushS();
    }
    if (simOv) for (const dt of simOv.deaths) g.appendChild(svg('circle', { cx: x(dt), cy: bottom - 3, r: 3.2, class: 'death-dot' }, svg('title', {}, `a Sim death at ${fmtT(dt)}`)));
    hovers.challenge = (t) => challengeCard(t);
    lanes.challenge.label.querySelector('.lane-sub').textContent = `${m.key === 'bars' ? 'health bars' : 'seconds to clear'} · ${simOv && (simOv.dps || simOv.dpsReal) ? 'the Sim\'s hero' : 'a typical hero'}`;
  }

  /** The zone boxes show the limits of the measure picked. */
  function syncZoneBoxes() {
    const sec = sections.challenge;
    if (!sec) return;
    const z = zonesNow();
    for (const inp of sec.ctl.querySelectorAll('input[data-zone]')) {
      if (document.activeElement !== inp) inp.value = z[inp.dataset.zone];
      const unit = inp.parentElement.querySelector('.tl-zone-unit');
      if (unit) unit.textContent = prefs.chal === 'bars' ? ' bars' : ' s';
    }
    const det = sec.body.querySelector('.tl-explain');
    if (det && det.dataset.measure !== prefs.chal) {
      const fresh = explainStrip('challenge', [lg('sw-easy', 'easy'), lg('sw-fair', 'fair'), lg('sw-hardz', 'hard'), lg('sw-chal', 'the estimate'), lg('sw-sim', 'the Sim'), lg('sw-death', 'a Sim death')]);
      fresh.dataset.measure = prefs.chal;
      det.replaceWith(fresh);
    }
  }

  function challengeCard(t) {
    const v = view;
    if (!v) return null;
    const j = TimelineModel.indexAt(v.ser, t);
    if (j < 0) return null;
    const cr = v.crowd[j];
    const m = chalMeasure();
    const zones = zonesNow();
    const box = el('div', { class: 'view-card' });
    box.appendChild(cardHead('Challenge', v.t[j], m.words));
    const c = m.est[j];
    const zone = TimelineModel.zoneOf(c, zones);
    const sv = m.sim ? simAt(m.sim, v.t[j]) : null;
    box.appendChild(el('div', { class: 'vc-big' }, el('b', { class: 'zone-' + zone, text: c == null ? '–' : m.fmt(c) }), c == null ? ' nothing alive' : ` ${m.words}: ${zone}`,
      sv != null ? el('span', { class: 'muted' }, ` · the Sim: ${m.fmt(sv)}`) : null));
    const clearS = v.clear[j];
    box.appendChild(el('div', { class: 'hc-line' }, 'Seconds to clear = the crowd\'s HP ', el('b', { text: fmtCount(cr.hp) }), ` (${fmtCount(cr.n)} creatures, bosses left out) ÷ the hero's damage `, el('b', { text: `${fmtCount(v.dps[j])} a second` }), v.dpsSim[j] === 1 ? ' (the Sim\'s full DPS)' : v.dpsSim[j] === 2 ? ' (the Sim\'s real damage a second: an older Sim)' : ' (typical: 20.4 × power²)', ` = ${clearS == null ? '–' : fmtN(clearS, 1) + ' s'}.`));
    box.appendChild(el('div', { class: 'hc-line' }, 'Health bars = the crowd\'s HP × bite ', el('b', { text: fmtCount(cr.threat) }), ` ÷ (his damage a second × his effective HP ${fmtCount(v.ehp[j])}${v.ehpSim[j] ? ', the Sim\'s' : ', typical: 100'}) = ${v.bars[j] == null ? '–' : fmtN(v.bars[j], 2)}: what clearing the screen would cost him if every creature on it bit him the whole time.`));
    if (cr.top.length) {
      const grid = el('div', { class: 'vc-grid' });
      for (const o of cr.top.slice(0, 5)) grid.appendChild(el('div', { class: 'vc-r' }, el('i', { class: 'vc-sw', style: `background:${App.creatureColor(o.id)}` }), el('span', { text: App.creatureName(o.id) }), el('b', { text: `${fmtCount(o.hp)} HP` }), el('span', { class: 'muted', text: `${fmtCount(o.n)} × ${fmtN(o.n > 0 ? o.hp / o.n : 0, 1)} · bite ${fmtCount(o.bite)}/s` })));
      box.appendChild(grid);
    }
    if (simOv) {
      const pw = simAt(simOv.power, v.t[j]);
      const near = simOv.deaths.filter((d) => Math.abs(d - v.t[j]) <= 15);
      const th = simAt(simOv.threat, v.t[j]);
      box.appendChild(el('div', { class: 'hc-line muted', text: `The Sim's hero: power ${pw == null ? '–' : fmtN(pw, 2)} (a fresh level-1 Drifter = 1)${th != null ? ` · its crowd's HP × bite ${fmtCount(th)}` : ''}${near.length ? ` · ${near.length} death${near.length === 1 ? '' : 's'} within 15 s` : ''}` }));
    }
    box.appendChild(el('div', { class: 'sp-note', text: `Zones: green under ${m.fmt(zones.easy)}, amber to ${m.fmt(zones.hard)}, red past it (the boxes in the section's bar). HP in play: each creature's row HP fixed from its start × the stage × creature_hp_mult × hero level ${App.S.level}.` }));
    return box;
  }

  // ------------------------------------------------------------------ Composition (pass 84)

  const COMP_H = 112, COMP_TOP = 9;
  /** The shares at run second t: [{id, n, share}] by the section's mode and source. */
  function compAt(t) {
    const v = view;
    if (prefs.compSrc === 'sim' && simOv && Object.keys(simOv.aliveBy).length) {
      const out = [];
      let all = 0;
      for (const [id, arr] of Object.entries(simOv.aliveBy)) { const a = simAt(arr, t); if (a != null && a > 1e-6) { out.push({ id, n: a, share: 0 }); all += a; } }
      for (const o of out) o.share = all > 0 ? o.n / all : 0;
      return out.sort((a, b) => b.n - a.n);
    }
    if (prefs.comp === 'spawned' && lastSpawn) return TimelineModel.spawnedBetween(lastSpawn.est, Model.estimateAt(lastSpawn.est, t - winSecs), Model.estimateAt(lastSpawn.est, t));
    if (!v) return [];
    return TimelineModel.compositionAt(v.ser, TimelineModel.indexAt(v.ser, t));
  }

  function renderComposition(w) {
    const s = clear(lanes.composition.svg);
    setHeight('composition', COMP_H);
    stageShade(s, COMP_H);
    const end = App.viewEnd();
    const step = Math.max(1, Math.round(3 * spp));
    const ts = [];
    for (let t = Math.floor(T0); t <= end; t += step) ts.push(t);
    const samples = ts.map((t) => compAt(t));
    // the ten largest over the view, the rest as "others"
    const tot = {};
    for (const sm of samples) for (const o of sm) tot[o.id] = (tot[o.id] || 0) + o.share;
    const ids = Object.keys(tot).sort((a, b) => tot[b] - tot[a]);
    const shown = ids.slice(0, 10);
    const top = COMP_TOP, bottom = COMP_H - 6;
    const y = (f) => bottom - f * (bottom - top);
    const g = svg('g', { class: 'comp', 'data-hover': 'composition' });
    g.appendChild(svg('rect', { x: 0, y: 0, width: w, height: COMP_H, class: 'sp-hit' }));
    const acc = samples.map(() => 0);
    const layers = shown.concat(ids.length > 10 ? ['__other'] : []);
    for (const id of layers) {
      const lower = acc.slice();
      samples.forEach((sm, k) => {
        if (id === '__other') acc[k] = sm.reduce((a, o) => a + o.share, 0);
        else { const o = sm.find((q) => q.id === id); acc[k] += o ? o.share : 0; }
      });
      const up = ts.map((t, k) => `${x(t)},${y(Math.min(acc[k], 1))}`);
      const dn = ts.map((t, k) => `${x(t)},${y(Math.min(lower[k], 1))}`).reverse();
      g.appendChild(svg('polygon', { points: up.concat(dn).join(' '), class: 'comp-area', fill: id === '__other' ? '#5a5955' : App.creatureColor(id) }, svg('title', {}, id === '__other' ? 'every other creature' : App.creatureName(id))));
    }
    for (const f of [0.25, 0.5, 0.75]) {
      g.appendChild(svg('line', { x1: 0, x2: w, y1: y(f), y2: y(f), class: 'grid' }));
      g.appendChild(svg('text', { x: 4, y: y(f) - 2, class: 'grid-text', text: `${f * 100}%` }));
    }
    hovers.composition = (t) => compCard(t);
    s.appendChild(g);
    const what = prefs.compSrc === 'sim' && simOv ? 'the Sim, on screen' : prefs.comp === 'spawned' ? `spawned in the past ${winSecs} s` : 'on screen, the estimate';
    lanes.composition.label.querySelector('.lane-sub').textContent = what;
  }

  function compCard(t) {
    const all0 = compAt(t);
    // the creatures under half a body and under half a percent are counted, not listed
    const list = all0.filter((o) => o.n >= 0.5 || o.share >= 0.005);
    const box = el('div', { class: 'view-card' });
    const what = prefs.compSrc === 'sim' && simOv ? `alive in the Sim ${simOv.id}` : prefs.comp === 'spawned' ? `spawned ${fmtT(Math.max(0, t - winSecs))}–${fmtT(t)} (the past ${winSecs} s)` : 'alive (the estimate)';
    box.appendChild(cardHead('Composition', t, what));
    if (!list.length) { box.appendChild(el('div', { class: 'hc-line muted', text: 'nobody' })); return box; }
    const all = all0.reduce((a, o) => a + o.n, 0);
    box.appendChild(el('div', { class: 'vc-big' }, el('b', { text: fmtCount(all) }), ` creatures, ${list.length} kind${list.length === 1 ? '' : 's'}`));
    const grid = el('div', { class: 'vc-grid' });
    for (const o of list.slice(0, 14)) grid.appendChild(el('div', { class: 'vc-r' }, el('img', { src: App.iconFor(o.id), alt: '' }), el('span', { text: App.creatureName(o.id) }), el('b', { text: `${Math.round(o.share * 100)}%` }), el('span', { class: 'muted', text: fmtCount(o.n) })));
    box.appendChild(grid);
    if (list.length > 14 || all0.length > list.length) box.appendChild(el('div', { class: 'hc-line muted', text: `… and ${Math.max(0, list.length - 14) + (all0.length - list.length)} more under one each` }));
    return box;
  }

  // ------------------------------------------------------------------ the floor curve's lane (pass 84)

  const FLOOR_H = 70;
  /** "+ Floor": a floor curve starting at 20 alive from 0:00 (one undo step). */
  function addFloor() {
    const tl = App.tl();
    if (Array.isArray(tl.floor_curve) && tl.floor_curve.length) { App.select({ kind: 'floor' }); return; }
    App.apply((d) => { d.floor_curve = [[0, 20], [App.stageLength(), 40]]; App.S.sel = { kind: 'floor' }; });
    App.toast('Started a floor curve: 20 alive at 0:00, 40 at the first boss (drag its points)', { undo: true });
  }

  function renderFloor(w) {
    const s = clear(lanes.floor.svg);
    setHeight('floor', FLOOR_H);
    stageShade(s, FLOOR_H);
    const tl = App.tl();
    const fc = Array.isArray(tl.floor_curve) ? tl.floor_curve : [];
    let maxV = 40;
    for (const p of fc) maxV = Math.max(maxV, Number(p[1]) || 0);
    maxV *= 1.2;
    const top = 8, bottom = FLOOR_H - 10;
    const y = (val) => bottom - (Math.max(0, val) / maxV) * (bottom - top);
    const end = App.viewEnd();
    const sorted = fc.filter((p) => Array.isArray(p)).slice().sort((a, b) => a[0] - b[0]);
    let pts = '';
    if (sorted.length) {
      for (let px = 0; px <= x(end); px += 3) pts += `${px},${y(Model.samplePoints(sorted, tAtPx(px)))} `;
      s.appendChild(svg('polyline', { points: pts, class: 'floor-edit-line' + issueClass('floor') }));
      const hit = svg('polyline', { points: pts, class: 'cap-hit' }, svg('title', {}, 'the floor curve: click to edit; double-click to add a point here'));
      hit.addEventListener('pointerdown', (e) => {
        if (e.button !== 0) return;
        e.stopPropagation();
        if (!isDoubleTap('floor-line', e)) { App.select({ kind: 'floor' }); return; }
        e.preventDefault();
        const t = Math.max(0, Math.round(tAt(e.clientX)));
        const r = lanes.floor.svg.getBoundingClientRect();
        const val = Math.max(0, Math.round(((bottom - (e.clientY - r.top)) / (bottom - top)) * maxV));
        App.apply((d) => { d.floor_curve.push([t, val]); App.sortPoints(d.floor_curve); App.S.sel = { kind: 'floor' }; });
        App.toast(`Added a floor point: ${fmtT(t)} → ${val} alive`);
      });
      s.appendChild(hit);
    } else {
      s.appendChild(svg('text', { x: 8, y: 26, class: 'hint-text', text: 'no floor: the director never spawns to keep a least number alive ("+ Floor" in the label starts one; the game as before pass 84)' }));
    }
    fc.forEach((p, k) => {
      if (!Array.isArray(p)) return;
      const c = svg('g', { class: 'cap-point floor-point', transform: `translate(${x(Number(p[0]) || 0)}, ${y(Number(p[1]) || 0)})` },
        svg('title', {}, `${fmtT(p[0])} → at least ${p[1]} alive (drag; double-click to remove)`),
        svg('circle', { r: 5.5 }), svg('text', { x: 8, y: -6, class: 'pt-text', text: String(p[1]) }));
      c.addEventListener('pointerdown', (e) => {
        if (e.button !== 0) return;
        if (!isDoubleTap(`floor-point:${p[0]}:${p[1]}`, e)) { startDrag(e, { kind: 'floor', k, y, maxV, top, bottom }); return; }
        e.stopPropagation(); e.preventDefault();
        App.apply((d) => { d.floor_curve.splice(k, 1); if (!d.floor_curve.length) delete d.floor_curve; App.S.sel = { kind: 'floor' }; });
        App.toast('Removed a floor point', { undo: true });
      });
      s.appendChild(c);
    });
    const b = issueBadge('floor', 14, 14);
    if (b) s.appendChild(b);
    lanes.floor.label.querySelector('.lane-sub').textContent = fc.length ? `${plural(fc.length, 'point')} · creatures alive at least` : 'none';
  }

  // ------------------------------------------------------------------ warnings (pass 84)

  let warnCache = null;
  /** What the estimate and the checks found: [{level 'warn'|'info', kind, text, short, t, key}]. */
  function warningsOf() {
    if (warnCache) return warnCache;
    const out = [];
    const v = view;
    const tl = App.tl();
    const rows = tl.roster || [];
    const est = lastSpawn ? lastSpawn.est : null;
    try {
      if (v && est) {
        // the cap full, and who starves there
        for (const r of fullRuns(v)) {
          if (r.b - r.a < 3) continue;
          const who = new Set();
          for (let j = r.j0; j <= r.j1; j += 2) for (const k of v.starving(j)) who.add(k);
          const list = [...who];
          out.push({ level: list.length ? 'warn' : 'info', kind: 'cap full', t: r.a, key: list[0] || null,
            text: `The cap is full from ${fmtT(r.a)} to ${fmtT(r.b)} (${fmtN(r.b - r.a, 0)} s)${list.length ? `: ${list.slice(0, 5).map(srcWords).join(', ')}${list.length > 5 ? ` and ${list.length - 5} more` : ''} wanted to spawn and starved` : ': every open row still got some in'}.`,
            short: `cap full ${fmtT(r.a)}–${fmtT(r.b)}` });
        }
        // rows the estimate never draws, and rows that never make 1% of what spawns
        const last = est.points[est.points.length - 1];
        rows.forEach((r, i) => {
          const key = `roster:${i}`;
          // a row the estimate files under no source of its own (an elite or roster-draw row: counted with the
          // elite-modified) is not judged here
          if (!(key in ((last || {}).src || {})) && (r.elite || r.enemy === 'roster' || Array.isArray(r.enemy))) return;
          const n = Number(((last || {}).src || {})[key]) || 0;
          if (n < 0.5) {
            out.push({ level: 'warn', kind: 'never spawns', t: Number(r.t) || 0, key, text: `${srcWords(key)} spawns nothing in the estimate (its presence, the cap, Max alive or its schedule hold it back).`, short: `${enemyWords(r)} never spawns` });
            return;
          }
          const t0 = Number(r.t) || 0, t1 = Math.min(r.until == null || r.until === '' ? App.viewEnd() : Number(r.until), App.viewEnd());
          let best = 0;
          // 10 s windows every 5 s from the second before its start (a point counts what came up to its second)
          for (let a = t0 - 1; a < t1; a += 5) { const ws = Model.windowShares(est, a, Math.min(a + 10, t1 + 1)); if (ws && ws.share[key] > best) best = ws.share[key]; }
          if (best < 0.01 && TimelineModel.paceOf(r) !== 'once') out.push({ level: 'info', kind: 'tiny share', t: t0, key, text: `${srcWords(key)} never makes 1% of what spawns in any 10 s of its life (≈${fmtCount(n)} in all).`, short: `${enemyWords(r)} under 1%` });
        });
        // the crowd's HP on screen more than doubling in a second
        const jumps = [];
        for (let j = 1; j < v.n; j++) {
          if (v.t[j] - v.t[j - 1] > 1.5 || v.t[j] === v.t[j - 1]) continue;
          if (v.alive[j - 1] < 10 || !(v.hp[j - 1] > 0)) continue;
          if (v.hp[j] > v.hp[j - 1] * 2) jumps.push({ j, f: v.hp[j] / v.hp[j - 1] });
        }
        jumps.sort((a, b) => b.f - a.f);
        for (const jp of jumps.slice(0, 6)) {
          const j = jp.j;
          const a = est.points[Math.max(0, j - 1)], b = est.points[j];
          let topKey = null, topN = 0;
          for (const k of Object.keys((b || {}).src || {})) { const d = (b.src[k] || 0) - ((a.src || {})[k] || 0); if (d > topN) { topN = d; topKey = k; } }
          out.push({ level: 'warn', kind: 'difficulty jump', t: v.t[j], key: topKey,
            text: `The crowd's HP on screen jumps ×${fmtN(jp.f, 1)} in one second at ${fmtT(v.t[j])} (${fmtCount(v.hp[j - 1])} → ${fmtCount(v.hp[j])} HP)${topKey ? `: mostly ${srcWords(topKey)} (≈${fmtCount(topN)})` : ''}.`, short: `×${fmtN(jp.f, 1)} jump at ${fmtT(v.t[j])}` });
        }
        // the floor above the cap
        const fc = Array.isArray(tl.floor_curve) ? tl.floor_curve.filter((p) => Array.isArray(p)).slice().sort((a, b) => a[0] - b[0]) : [];
        if (fc.length) {
          const fo = TimelineModel.floorOverCap((t) => Model.samplePoints(fc, t), (t) => v.capB[Math.max(0, TimelineModel.indexAt(v.ser, t))], App.viewEnd(), 5);
          if (fo) out.push({ level: 'warn', kind: 'floor over cap', t: fo.t, key: 'floor', text: `The floor (${Math.round(fo.floor)} alive) is above the cap at ${fmtT(fo.t)} (it holds about ${Math.round(fo.cap)} bodies at the crowd's mix): the director can never reach it.`, short: `floor over the cap at ${fmtT(fo.t)}` });
        }
      }
      // overlapping identical rows
      for (const [i, k] of TimelineModel.overlappingTwins(rows, App.viewEnd())) {
        out.push({ level: 'warn', kind: 'twin rows', t: Math.max(Number(rows[i].t) || 0, Number(rows[k].t) || 0), key: `roster:${k}`,
          text: `Rows ${rows[i].id || i + 1} and ${rows[k].id || k + 1} are the same (${enemyWords(rows[i])}, the same schedule, look and overrides) and overlap: one row with the two weights added does the same.`, short: `rows ${rows[i].id || i + 1} = ${rows[k].id || k + 1}` });
      }
    } catch (e) { console.error('warnings', e); }
    out.sort((a, b) => (a.level === b.level ? (a.t || 0) - (b.t || 0) : a.level === 'warn' ? -1 : 1));
    warnCache = out;
    return out;
  }

  /** Go to a warning: open its section and group, select its row (or the floor), bring its second into view. */
  function goTo(wn) {
    if (wn.key && wn.key.startsWith('roster:')) {
      const i = Number(wn.key.split(':')[1]);
      const r = (App.tl().roster || [])[i];
      if (r) { delete secState.rows; delete secState['group:' + groupOf(r, prefs.group).key]; saveSecState(); }
      App.select({ kind: 'roster', i }, { scroll: true });
    } else if (wn.key === 'floor') { delete secState.curves; saveSecState(); App.select({ kind: 'floor' }); }
    if (wn.t != null) scrollToTime(wn.t);
  }

  function scrollToTime(t) {
    if (!scrollBox) return;
    const visible = scrollBox.clientWidth - LABEL_W;
    const px = x(Number(t) || 0);
    if (px < scrollBox.scrollLeft + 20 || px > scrollBox.scrollLeft + visible - 20) scrollBox.scrollLeft = Math.max(0, px - visible / 3);
  }

  function renderWarnings() {
    const host = sections.warnings ? sections.warnings.body.querySelector('.tl-warn') : null;
    if (!host) return;
    clear(host);
    const ws = warningsOf();
    const iss = App.S.issues || { errors: [], warnings: [] };
    host.appendChild(el('div', { class: 'tl-warn-head' },
      el('b', { text: ws.length ? `${ws.length} found by the estimate` : 'The estimate finds nothing to warn about' }),
      el('span', { class: 'muted small', text: 'What it looks for: the cap full with rows starving, rows that never spawn or never make 1% of what spawns, the crowd\'s HP more than doubling in a second, a floor above the cap, two identical rows overlapping. An estimate: check a doubt with the Sim.' }),
      el('span', { class: 'spacer' }),
      iss.errors.length || iss.warnings.length ? el('button', { class: 'btn small', type: 'button', text: `The checks: ${iss.errors.length} error${iss.errors.length === 1 ? '' : 's'}, ${iss.warnings.length} warning${iss.warnings.length === 1 ? '' : 's'}`, title: 'the map\'s checks (errors block Save) in the inspector', onclick: () => App.select(null) }) : el('span', { class: 'muted small', text: 'the map\'s checks: no issues' })));
    const list = el('div', { class: 'tl-warn-list' });
    for (const wn of ws.slice(0, 40)) {
      list.appendChild(el('div', { class: 'tl-warn-row ' + wn.level },
        U.glyph(wn.level === 'warn' ? 'warn' : 'flag'), el('span', { class: 'tl-warn-kind', text: wn.kind }), el('span', { class: 'tl-warn-text', text: wn.text }),
        el('button', { class: 'btn small', type: 'button', text: 'Go to', title: `select it and scroll to ${fmtT(wn.t)}`, onclick: () => goTo(wn) })));
    }
    if (ws.length > 40) list.appendChild(el('div', { class: 'muted small', text: `… and ${ws.length - 40} more` }));
    host.appendChild(list);
  }

  /** A row's spawns a second over its life and its HP in play each second (the inspector's mini-chart, pass 84):
   *  {ts, n, hp} from the estimate drawn last; null before it is. */
  function rowSpawnsPerSecond(i) {
    const est = lastSpawn ? lastSpawn.est : null;
    const r = (App.tl().roster || [])[i];
    if (!est || !r) return null;
    const key = `roster:${i}`;
    const t0 = Math.max(0, Math.floor(Number(r.t) || 0));
    const t1 = Math.min(Math.ceil(rowBarEnd(r, App.viewEnd())), Math.floor(App.viewEnd()));
    const c = App.creature(firstEnemy(r));
    const ts = [], n = [], hp = [];
    let prev = Number(((Model.estimateAt(est, t0 - 1) || {}).src || {})[key]) || 0;
    for (let t = t0; t <= Math.max(t0, t1); t++) {
      const cur = Number(((Model.estimateAt(est, t) || {}).src || {})[key]) || 0;
      ts.push(t); n.push(Math.max(0, cur - prev)); prev = cur;
      hp.push(c ? App.creatureAt(c, r.stats || {}, t, Number(r.t) || 0).hp : null);
    }
    return { ts, n, hp };
  }

  // ------------------------------------------------------------------ "+ Row" (pass 84)

  /** The "+ Row" menu: a row of each kind at the view's centre (App.newRowPreset). */
  function rowMenu(anchor) {
    closeMenu();
    menu = el('div', { class: 'menu' });
    const items = [
      ['continuous', 'Continuous', 'drawn into the cap by its weight at every spawn check (the plain crowd)'],
      ['waves', 'Waves every N s', 'a wave of Per wave creatures every Every seconds while it is open'],
      ['once', 'Once: a swarm', 'one burst of 30 on top of the cap, on a ring 16 m out, with a SWARM! banner (what the swarm events were)'],
      ['elite', 'Once: a coloured elite', 'one creature from the roster draw wearing a random elite modifier (what the coloured-elite events were)'],
      ['elite_every', 'Elites every', 'a coloured elite from the roster draw every 110-150 s from here on (what the Elites-every event was)'],
      ['special', 'Once: a special', 'one creature as its coloured special, from the top of the screen (the special Goblin at 2:00)'],
    ];
    for (const [kind, label, help] of items) menu.appendChild(el('button', { class: 'menu-item', onclick: () => { closeMenu(); App.newRowPreset(kind, viewCenter()); } }, glyph(kind === 'elite' || kind === 'elite_every' ? 'star' : kind === 'once' ? 'ring' : kind === 'waves' ? 'repeat' : 'flag'), el('span', { text: label }), el('small', { text: help })));
    document.body.appendChild(menu);
    const r = anchor.getBoundingClientRect();
    const mh = menu.offsetHeight, mw = menu.offsetWidth;
    menu.style.left = `${Math.max(4, Math.min(r.left, window.innerWidth - mw - 8))}px`;
    menu.style.top = `${r.bottom + 4 + mh <= window.innerHeight - 8 ? r.bottom + 4 : Math.max(4, r.top - 4 - mh)}px`;
    setTimeout(() => document.addEventListener('pointerdown', onDocDown, { once: true }), 0);
  }

  // ------------------------------------------------------------------ ruler

  function tickStep() {
    for (const s of [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1200]) if (s / spp >= 72) return s;
    return 1800;
  }

  function renderRuler(w) {
    const s = clear(lanes.ruler.svg);
    setHeight('ruler', RULER_H);
    const n = App.stages(), end = App.viewEnd();
    const names = ['stage-1', 'stage-2', 'stage-3', 'stage-4'];
    const vs = App.viewStage();
    // pass 87 (lane STOOLS): each stage's own window (stage_list), its band a button that opens its settings
    for (const wdw of App.stageList()) {
      const k = wdw.i, a = wdw.start, b = Math.min(wdw.end, end);
      if (b < T0) continue;
      const fl = typeof StageModel !== 'undefined' ? StageModel.filterOf(wdw.entry) : null;
      const band = svg('g', { class: 'stage-band' + (App.selKey() === `stage:${k}` ? ' selected' : ''), onpointerdown: (e) => { if (e.button === 0) { e.stopPropagation(); App.select({ kind: 'stage', i: k }); } } });
      band.appendChild(svg('rect', { x: x(a), y: 0, width: Math.max(0, x(b) - x(a)), height: 20, class: 'band ' + names[Math.min(k, 3)] }));
      if (fl && fl.strength > 0) band.appendChild(svg('rect', { x: x(a), y: 16, width: Math.max(0, x(b) - x(a)), height: 4, fill: fl.color, opacity: Math.min(1, 0.35 + fl.strength) }));
      band.appendChild(svg('text', { x: Math.max(x(a), 0) + 6, y: 14, class: 'band-text', text: `Stage ${k + 1}${wdw.name !== `Stage ${k + 1}` ? ' · ' + wdw.name : ''}  ${fmtT(a)} – ${fmtT(wdw.end)} (${fmtT(wdw.length)})  ×${fmtN(App.stageMult(k), 2)}` }));
      band.appendChild(svg('title', {}, `Stage ${k + 1}: click for its settings (name, length, boss, words, colour)`));
      s.appendChild(band);
    }
    if (vs == null) {
      s.appendChild(svg('rect', { x: x(App.runEnd()), y: 0, width: Math.max(0, x(end) - x(App.runEnd())) + 60, height: 20, class: 'band endless' }));
      s.appendChild(svg('text', { x: x(App.runEnd()) + 6, y: 14, class: 'band-text', text: `after the last boss: the portal's ${fmtT(App.portalSeconds())}, then Endless` }));
    } else {
      // a stage tab: its boss, the portal's timer (only Extract), then Endless
      const be = App.stageEnd(vs), pe = be + App.portalSeconds();
      s.appendChild(svg('rect', { x: x(be), y: 0, width: Math.max(0, x(pe) - x(be)), height: 20, class: 'band portal-band' }));
      s.appendChild(svg('text', { x: x(be) + 6, y: 14, class: 'band-text', text: `portal ${fmtT(App.portalSeconds())}` }, svg('title', {}, 'after the boss: the portal opens with a timer and only EXTRACT; when it runs out, Endless starts')));
      s.appendChild(svg('rect', { x: x(pe), y: 0, width: Math.max(0, x(end) - x(pe)) + 60, height: 20, class: 'band endless' }));
      s.appendChild(svg('text', { x: x(pe) + 6, y: 14, class: 'band-text', text: `Endless: ${Model.endlessWaveSize(App.tl(), 1, vs)} at once, then a wave every ${fmtN(Model.endlessValue(App.tl(), 'every', vs), 0)} s, each tougher` }));
    }
    const step = tickStep();
    // a stage tab ticks the stage run's own clock (0:00 at its window's start); All, the map's
    for (let t = T0; t <= end; t += step / 2) {
      const major = Math.abs(((t - T0) / step) - Math.round((t - T0) / step)) < 1e-6;
      s.appendChild(svg('line', { x1: x(t), x2: x(t), y1: major ? 24 : 32, y2: 40, class: major ? 'tick' : 'tick minor' }));
      if (major) {
        // a stage tab counts the stage run's own clock (0:00 at the window's start), the map's clock beside it, smaller
        if (vs == null) s.appendChild(svg('text', { x: x(t) + 3, y: 54, class: 'tick-text', text: fmtT(t) }));
        else s.appendChild(svg('text', { x: x(t) + 3, y: 54, class: 'tick-text' }, svg('tspan', { text: fmtT(t - T0) }), svg('tspan', { class: 'tick-map', dx: 4, text: `(${fmtT(t)})` })));
      }
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
    lanes.ruler.label.querySelector('.lane-sub').textContent = vs == null
      ? `${n} stage${n === 1 ? '' : 's'}: ${App.stageList().map((wd) => fmtT(wd.length)).join(' + ')}`
      : `stage ${vs + 1}'s own clock (the map's in brackets)`;
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
      for (let px = 0; px <= x(end); px += 4) pts += `${px},${y(App.hellCapAt(tAtPx(px)))} `;
      s.appendChild(svg('polyline', { points: pts, class: 'hell-cap' }, svg('title', {}, 'the hell channel\'s cap (hell_cap × the regular cap)')));
    }
    // the effective cap, sampled (cap_max and cap_per_stage apply on top of the curve)
    let pts = '';
    for (let px = 0; px <= x(end); px += 3) pts += `${px},${y(App.capAt(tAtPx(px)))} `;
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
    const SE = App.stageEnd(App.viewStage() == null ? 0 : App.viewStage());
    const atStage = Model.estimateAt(est, SE, true);
    lanes.spawned.label.querySelector('.lane-sub').textContent = `estimate · ${fmtCount(atStage ? atStage.all : 0)} by ${fmtT(SE)}`;
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
    for (let px = 0; px <= x(end); px += 3) line += `${px},${y(f(tAtPx(px)))} `;
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
    for (let px = 0; px <= x(end); px += 3) line += `${px},${y(f(tAtPx(px)))} `;
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
          const seeded = Model.stageMarks(App.tl()).map((mt) => [mt, Model.round(f(mt), 4)]);
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

  // pass 84 (lane TIMELINE): the spawn rows grouped (by stage, role, both or none; each group folds to a bar), coloured
  // by role (or by creature), each bar saying how many and how often, its HP and ATK at its start and its badges
  const GROUP_H = 22;
  let rosterLay = null;               // the layout drawn last: {items, yOf, height}

  /** A row's group under `mode`: {key, label, order, role}. */
  function groupOf(r, mode) {
    const st = App.stageAt(Number(r.t) || 0);
    const stName = st >= App.stages() ? 'Endless' : `Stage ${st + 1}`;
    const role = TimelineModel.roleOf(r);
    const ri = Math.max(0, TimelineModel.ROLES.findIndex((x) => x.v === role));
    const rl = TimelineModel.roleInfo(role).label;
    if (mode === 'role') return { key: 'r' + role, label: `${rl}`, order: ri, role };
    if (mode === 'stage_role') return { key: `s${st}r${role}`, label: `${stName} · ${rl}`, order: st * 100 + ri, role };
    return { key: 's' + st, label: stName, order: st * 100, role: null };
  }

  /** Where each row and group header sits on the lane. */
  function rosterLayout(rows) {
    const mode = prefs.group;
    const items = [];
    const yOf = {};
    let y = ROSTER_HEAD;
    if (mode === 'none') {
      rows.forEach((r, i) => { if (!rowInView(r)) return; items.push({ type: 'row', i, y }); yOf[i] = y; y += ROW_H; });
      return { items, yOf, height: y, mode };
    }
    const groups = new Map();
    rows.forEach((r, i) => {
      if (!rowInView(r)) return;
      const g = groupOf(r, mode);
      if (!groups.has(g.key)) groups.set(g.key, Object.assign(g, { rows: [] }));
      groups.get(g.key).rows.push(i);
    });
    const order = [...groups.values()].sort((a, b) => a.order - b.order || (a.key < b.key ? -1 : 1));
    for (const g of order) {
      // the rows of a group in the order of their start (the file's order breaks a tie)
      g.rows.sort((a, b) => (Number(rows[a].t) || 0) - (Number(rows[b].t) || 0) || a - b);
      const collapsed = isCollapsed('group:' + g.key);
      items.push({ type: 'group', g, y, collapsed });
      y += GROUP_H;
      if (!collapsed) for (const i of g.rows) { items.push({ type: 'row', i, y }); yOf[i] = y; y += ROW_H; }
    }
    return { items, yOf, height: y, mode };
  }

  /** Pass 87 (lane STOOLS): whether a row shows on the open tab: every row on "All"; on a stage tab the rows open at
   *  some second of its window (from its start to its boss; a row spanning windows shows on both tabs). */
  function rowInView(r) {
    const vs = App.viewStage();
    if (vs == null) return true;
    const a = App.stageStart(vs), b = App.stageEnd(vs);
    const t0 = Number(r.t) || 0;
    const t1 = r.until == null || r.until === '' ? Infinity : Number(r.until);
    return t0 < b && t1 > a;
  }

  /** A row's numbers in play at its start (HP, ATK), from lane SPAWN's shown difficulty when the model has it
   *  (Model.creatureDifficulty: a once row its own second, the mix row it joins), else the page's creatureAt (the stage, creature_*_mult and the hero level box on top of the
   *  row's numbers fixed from its start). Null for the roster draw. */
  function startNumbers(r) {
    const id = firstEnemy(r);
    const c = App.creature(id);
    if (!c) return null;
    const t0 = Number(r.t) || 0;
    if (typeof Model.creatureDifficulty === 'function') {
      try { const d = Model.creatureDifficulty(App.tl(), c, r, TimelineModel.paceOf(r) === 'once' ? Model.rowWaveStart(r) : t0, { level: App.S.level, byId: App.S.byId }); if (d && d.hp != null) return { hp: d.hp, atk: d.atk }; } catch (_) { /* the page's own */ }
    }
    const at = App.creatureAt(c, r.stats || {}, t0, t0);
    return { hp: at.hp, atk: at.atk };
  }

  /** Spawns a minute of a continuous row over its open life (the estimate), null before it is drawn. */
  function perMinute(i, r) {
    const est = lastSpawn ? lastSpawn.est : null;
    if (!est) return null;
    const t0 = Number(r.t) || 0;
    const t1 = Math.min(r.until == null || r.until === '' ? App.runEnd() : Number(r.until), App.viewEnd());
    if (!(t1 > t0 + 1)) return null;
    const a = Model.estimateAt(est, t0, true), b = Model.estimateAt(est, t1);
    const nb = Number(((b && b.src) || {})[`roster:${i}`]) || 0, na = Number(((a && a.src) || {})[`roster:${i}`]) || 0;
    const n = Math.max(0, nb - na);
    return n / ((t1 - t0) / 60);
  }

  /** The bar's end on the lane: its until, the view's end when open; a once row with no until is a short block. */
  function rowBarEnd(r, end) {
    const t = Number(r.t) || 0;
    if (r.until != null && r.until !== '') return Math.max(t, Math.min(Number(r.until), end));
    if (TimelineModel.paceOf(r) === 'once') return Math.min(end, Model.rowWaveStart(r) + Math.max(10, 46 * spp));
    return end;
  }

  function renderRoster(w) {
    const s = clear(lanes.roster.svg);
    const rows = App.tl().roster || [];
    const lay = rosterLayout(rows);
    rosterLay = lay;
    const h = lay.height + PAD;
    setHeight('roster', Math.max(h, ROSTER_HEAD + ROW_H));
    const end = App.viewEnd();
    stageShade(s, Math.max(h, ROSTER_HEAD + ROW_H));
    // one weight scale for every row, so their areas compare (held while a presence point is dragged)
    let maxW = 1;
    for (const r of rows) {
      if (Array.isArray(r.weights) && r.weights.length) for (const p of r.weights) maxW = Math.max(maxW, Number(p[1]) || 0);
      else maxW = Math.max(maxW, App.rowWeight(r, Number(r.t) || 0));
    }
    if (frozenMax != null) maxW = frozenMax;
    s.appendChild(svg('text', { x: 6, y: 25, class: 'hint-text', text: `a bar's filled height is its presence weight (full bar = ${fmtN(maxW, 2)}); drag a point, double-click the bar to add one, a point to remove it` }));
    const bh = ROW_H - 6, span = bh - 6;
    // the group bars: a band across the lane (hatched when folded, with each row's span as a thin line)
    for (const it of lay.items) {
      if (it.type !== 'group') continue;
      const gcol = it.g.role != null ? TimelineModel.roleColor(it.g.role) : '#8a8880';
      const band = svg('g', { class: 'grp-band' + (it.collapsed ? ' collapsed' : '') });
      band.appendChild(svg('rect', { x: 0, y: it.y, width: w, height: GROUP_H, class: 'grp-bg' }));
      band.appendChild(svg('rect', { x: 0, y: it.y + GROUP_H - 2, width: w, height: 2, fill: gcol, opacity: 0.55 }));
      if (it.collapsed) {
        it.g.rows.forEach((i, k) => {
          const r = rows[i];
          const t = Number(r.t) || 0;
          const x0 = x(t), x1 = Math.max(x0 + 3, x(rowBarEnd(r, end)));
          const yy = it.y + 4 + (k % 7) * 2;
          band.appendChild(svg('line', { x1: x0, x2: x1, y1: yy, y2: yy, class: 'grp-span', stroke: prefs.colour === 'creature' ? App.creatureColor(firstEnemy(r)) : TimelineModel.roleColor(TimelineModel.roleOf(r)) }));
        });
      }
      s.appendChild(band);
    }
    for (const it of lay.items) {
      if (it.type !== 'row') continue;
      const i = it.i;
      const r = rows[i];
      const key = `roster:${i}`;
      const t = Number(r.t) || 0;
      const open = (r.until == null || r.until === '') && TimelineModel.paceOf(r) !== 'once';
      const tEnd = Math.max(t, rowBarEnd(r, end));
      const x0 = x(t), x1 = Math.max(x0 + 4, x(tEnd));
      const y0 = it.y + 3;
      const fid = firstEnemy(r);
      const c = App.creature(fid);
      const role = TimelineModel.roleOf(r);
      const col = prefs.colour === 'creature' ? App.creatureColor(fid || 'roster') : TimelineModel.roleColor(role);
      const yb = y0 + bh - 3;
      const yW = (val) => yb - (Math.max(0, val) / maxW) * span;
      const pace = TimelineModel.paceOf(r);
      const g = svg('g', { class: 'bar pace-' + pace + (r.channel === 'hell' ? ' hell' : '') + (role ? ' role-' + role : ' untagged') + (App.selKey() === key ? ' selected' : '') + (snapIs('roster', i) ? ' snap-target' : '') + issueClass(key), 'data-key': key, 'data-hover': key });
      g.appendChild(svg('rect', { x: x0, y: y0, width: x1 - x0, height: bh, rx: 4, class: 'bar-body', style: `stroke:${col}` }));
      g.appendChild(svg('rect', { x: x0, y: y0, width: 3, height: bh, class: 'bar-role', fill: col }));
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
      // pass 87: a bar that starts before a stage tab's window keeps its icon and words at the window's left edge
      const lx0 = Math.max(x0, 0);
      if (c) inner.appendChild(svg('image', { href: App.iconFor(fid, r.variant), x: lx0 + 5, y: y0 + 1.5, width: 17, height: 17, preserveAspectRatio: 'xMidYMid meet' }));
      let tx = lx0 + 26;
      const nm = `${r.name ? r.name + ' · ' : ''}${enemyWords(r)}`;
      inner.appendChild(svg('text', { x: tx, y: y0 + 13, class: 'bar-text', text: nm }));
      tx += textWidth(nm, 12) + 8;
      // how many and how often, then the numbers at its start
      const qty = TimelineModel.quantityText(r, Model.rowWaveCount(r, c), pace === 'continuous' ? perMinute(i, r) : null);
      tx = chip(inner, tx, y0 + 2, { text: qty, cls: 'chip-qty' + (pace !== 'continuous' ? ' paced' : ''), title: `${pace === 'continuous' ? 'continuous: spawned a minute over its open life (the estimate)' : pace === 'once' ? 'one wave' : 'paced as waves'}${r.respect_cap === false ? ', on top of the cap' : ''}` });
      const sn = startNumbers(r);
      if (sn) {
        const nt = `HP ${fmtN(sn.hp, sn.hp >= 100 ? 0 : 1)} · ATK ${fmtN(sn.atk, 1)}`;
        inner.appendChild(svg('text', { x: tx, y: y0 + 13, class: 'bar-num', text: nt }, svg('title', {}, `in play at its start (${fmtT(t)}): the row's numbers fixed there × the stage × creature_hp_mult / creature_damage_mult × hero level ${App.S.level}`)));
        tx += textWidth(nt, 11) + 8;
      }
      const first = ws.length ? ws[0].w : App.rowWeight(r, t), last = ws.length ? ws[ws.length - 1].w : first;
      const wt = ws.length > 2 ? `w ${fmtN(first)} → … → ${fmtN(last)}` : first !== last ? `w ${fmtN(first)} → ${fmtN(last)}` : `w ${fmtN(first)}`;
      inner.appendChild(svg('text', { x: tx, y: y0 + 13, class: 'bar-sub', text: wt }));
      tx += textWidth(wt, 11) + 8;
      const chips = [];
      if (r.elite != null && r.elite !== '') chips.push({ text: `★ ${r.elite === 'random' ? 'elite' : r.elite}`, cls: 'chip-elite', title: `every creature wears ${r.elite === 'random' ? 'a random elite modifier' : `the ${r.elite} modifier`} (after Colour after kills)` });
      if (r.special === true) chips.push({ text: '◆ special', cls: 'chip-special', title: 'every creature comes as its coloured special' });
      if (r.banner) chips.push({ text: `⚑ ${r.banner}`, cls: 'chip-toast', title: 'the banner the player reads when it fires' });
      if (r.channel === 'hell') chips.push({ text: 'hell', cls: 'chip-hell', title: 'the hell channel: its own cap' });
      if (r.variant) chips.push({ text: r.variant, cls: 'chip-variant' });
      if (r.pack != null) chips.push({ text: `×${r.pack}`, cls: 'chip-pack' });
      if (r.pattern && r.pattern !== 'pack') chips.push({ text: patternLabel(r.pattern) + (r.pattern === 'ring' && r.ring_radius != null ? ` ${fmtN(r.ring_radius, 1)} m` : ''), cls: 'chip-pattern' });
      if (r.respect_cap === false && pace !== 'continuous') chips.push({ text: 'no cap', cls: 'chip-nocap', title: 'on top of the cap (the hard cap still holds)' });
      // pass 58: a size range and a swatch of the colour range
      const sr = Model.sizeRange(r.stats && r.stats.size);
      if (sr && sr.range) chips.push(sr.min === sr.max ? { text: `${fmtN(sr.min, 2)} m`, cls: 'chip-size', title: 'every creature of the row this size (a list of one size: no spread)' } : { text: `${fmtN(sr.min, 2)}–${fmtN(sr.max, 2)} m`, cls: 'chip-size', title: 'each creature of the row its own size in this range' });
      const tr = Model.tintRange(r.stats && r.stats.tint);
      if (tr) chips.push({ hue: tr, cls: 'chip-hue', title: `coloured ${Math.round(tr.h0)}°–${Math.round(tr.h1)}° at ${Math.round(tr.amount * 100)}%` });
      if (r.stats && Object.keys(r.stats).length) chips.push({ glyph: 'wrench', cls: 'chip-wrench' });
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
    }
    if (!rows.length) s.appendChild(svg('text', { x: 8, y: ROSTER_HEAD + 18, class: 'hint-text', text: 'no spawn rows: "+ Row" adds one at the view\'s centre' }));
    const hell = rows.filter((r) => r.channel === 'hell').length;
    const shownN = lay.items.filter((it) => it.type === 'row').length + lay.items.filter((it) => it.type === 'group' && it.collapsed).reduce((a, it) => a + it.g.rows.length, 0);
    lanes.roster.label.querySelector('.lane-sub').textContent = App.viewStage() == null
      ? `${plural(rows.length, 'row')}${hell ? ` · ${hell} hell` : ''}`
      : `${shownN} of ${plural(rows.length, 'row')} in stage ${App.viewStage() + 1}${hell ? ` · ${hell} hell` : ''}`;
    renderGutter(rows, lay);
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
    } else if (TimelineModel.paceOf(r) === 'once') {
      // pass 84: a once row's one wave (the model plays it when lane SPAWN's rowEtchTimes knows `once`)
      const tk = Model.rowWaveStart(r);
      if (tk >= t0 && tk <= t1 + 1e-9 && App.rowWeight(r, tk) > 0) g.appendChild(svg('line', { x1: x(tk), x2: x(tk), y1: yf - 1, y2: yf - 11, class: 'etch-tick once' }));
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

  /** The roster's gutter in the sticky label column (pass 84: grouped): a bar per group (its chevron, name and count; a
   *  click folds or opens it), per row a grip to drag it up or down (with no groups), ▲ / ▼ (within its group), its icon
   *  and name (a click selects the row). The order is for this page only: the game draws by weight. */
  function renderGutter(rows, lay) {
    const gut = lanes.roster.label.querySelector('.gutter');
    clear(gut);
    const L = lay || rosterLayout(rows);
    const grouped = L.mode !== 'none';
    // the visible order inside each group, for ▲ / ▼
    const order = L.items.filter((it) => it.type === 'row').map((it) => it.i);
    for (const it of L.items) {
      if (it.type === 'group') {
        const gcol = it.g.role != null ? TimelineModel.roleColor(it.g.role) : '';
        const head = el('div', { class: 'gut-group' + (it.collapsed ? ' collapsed' : ''), style: `top:${it.y}px;height:${GROUP_H}px`, title: it.collapsed ? `${it.g.label}: folded, click to open` : `${it.g.label}: click to fold` },
          el('span', { class: 'gut-chev', text: it.collapsed ? '▸' : '▾' }), gcol ? el('i', { class: 'gut-sw', style: `background:${gcol}` }) : null,
          el('b', { text: it.g.label }), el('span', { class: 'muted', text: ` ${it.g.rows.length}${it.collapsed ? ' · folded' : ''}` }));
        head.addEventListener('click', (e) => { e.stopPropagation(); setCollapsed('group:' + it.g.key, !it.collapsed); });
        gut.appendChild(head);
        continue;
      }
      const i = it.i;
      const r = rows[i];
      const sel = App.selKey() === `roster:${i}`;
      const k = order.indexOf(i);
      const same = (j) => j >= 0 && j < order.length && (!grouped || groupOf(rows[order[j]], L.mode).key === groupOf(r, L.mode).key);
      const up = same(k - 1) ? order[k - 1] : -1, down = same(k + 1) ? order[k + 1] : -1;
      const grip = grouped ? el('span', { class: 'grip off', title: 'reordering by dragging works with no groups (Spawn rows: group "no groups"); ▲ / ▼ move the row', text: '·' }) : el('span', { class: 'grip', title: 'drag up or down to reorder (the order is for this page only)', text: '⠿' });
      if (!grouped) grip.addEventListener('pointerdown', (e) => startReorder(e, i, rows.length));
      const pick = () => App.select({ kind: 'roster', i }, { scroll: true });
      const role = TimelineModel.roleOf(r);
      const fid = firstEnemy(r);
      gut.appendChild(el('div', { class: 'gut-row' + (sel ? ' selected' : '') + (r.channel === 'hell' ? ' hell' : ''), style: `top:${it.y}px;height:${ROW_H}px;box-shadow:inset 3px 0 0 ${TimelineModel.roleColor(role)}` },
        grip,
        el('button', { class: 'gut-btn', type: 'button', text: '▲', title: grouped ? 'move up within its group (the file\'s order changes; the game ignores it)' : 'move up (Alt+↑)', disabled: grouped ? up < 0 : i === 0, onclick: (e) => { e.stopPropagation(); if (grouped) App.moveRowTo(i, up); else App.moveRow(i, -1); } }),
        el('button', { class: 'gut-btn', type: 'button', text: '▼', title: grouped ? 'move down within its group' : 'move down (Alt+↓)', disabled: grouped ? down < 0 : i === rows.length - 1, onclick: (e) => { e.stopPropagation(); if (grouped) App.moveRowTo(i, down); else App.moveRow(i, 1); } }),
        fid ? el('img', { src: App.iconFor(fid, r.variant), width: 18, height: 18, alt: '', onclick: pick }) : el('span', { class: 'gut-ico', text: '★', onclick: pick }),
        el('span', { class: 'gut-name', text: r.name || enemyWords(r), title: `${r.name ? r.name + ': ' : ''}${enemyWords(r)}${r.id ? ` (${r.id})` : ''}${role ? ` · ${role}` : ''}: click to select`, onclick: pick })));
    }
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
    // pass 87: each stage's own window (stage_list); a stage tab shades what comes after its boss (portal, Endless)
    const L = App.stageList();
    for (const wd of L) if (wd.i % 2 === 1) s.appendChild(svg('rect', { x: x(wd.start), y: 0, width: Math.max(0, x(wd.end) - x(wd.start)), height: h, class: 'stage-shade' }));
    const after = App.viewStage() == null ? App.runEnd() : App.stageEnd(App.viewStage());
    s.appendChild(svg('rect', { x: x(after), y: 0, width: Math.max(0, x(App.viewEnd()) - x(after)) + 60, height: h, class: 'endless-shade' }));
    for (const wd of L) s.appendChild(svg('line', { x1: x(wd.end), x2: x(wd.end), y1: 0, y2: h, class: 'stage-line' }));
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
    // pass 84 (lane TIMELINE): the portal after each boss: its wave (portal_wave.count) or its cap for a while
    const tl84 = App.tl();
    const pw = Number(((tl84.portal_wave || {}).count) || 0);
    const pcap = tl84.portal_cap == null ? 10 : Number(tl84.portal_cap), psec = tl84.portal_spawn_seconds == null ? 30 : Number(tl84.portal_spawn_seconds);
    for (const e of evs) {
      if (e.ev.type !== 'boss') continue;
      const px = x(e.t) + 14;
      const words = pw > 0 ? `portal wave ${pw}` : pcap === 0 ? 'portal: nothing' : `portal: cap ${pcap < 0 ? 'as the stage ended' : pcap}${psec >= 0 ? ` for ${psec} s` : ''}`;
      const pg = svg('g', { class: 'portal-mark' + (App.selKey() === 'portal' ? ' selected' : ''), 'data-hover': 'portal' },
        svg('rect', { x: px - 2, y: EV_H - 22, width: textWidth(words, 10.5) + 24, height: 18, rx: 9, class: 'portal-bg' }),
        svg('use', { href: '#g-ring', x: px + 2, y: EV_H - 20, width: 14, height: 14, fill: '#b28cff' }),
        svg('text', { x: px + 19, y: EV_H - 9, class: 'portal-text', text: words }));
      pg.addEventListener('pointerdown', (ev2) => { if (ev2.button !== 0) return; ev2.stopPropagation(); App.select({ kind: 'portal' }); });
      s.appendChild(pg);
    }
    hovers.portal = () => {
      const box = el('div', {}, el('div', { class: 'hc-head' }, el('b', { text: 'The portal after a boss' })));
      box.appendChild(el('div', { class: 'hc-line', text: pw > 0 ? `One wave of ${pw} creatures of the rows open as the stage ended, round the hero as the portal opens; then nothing until he steps through.` : `The crowd is kept up to ${pcap < 0 ? 'the stage-end cap' : pcap} load units ${psec >= 0 ? `for ${psec} s after the boss dies` : 'while the portal waits'}; no specials.` }));
      box.appendChild(el('div', { class: 'hc-line muted', text: 'Click to edit (portal_wave.count, portal_cap, portal_spawn_seconds).' }));
      return box;
    };
    const olds = evs.filter((e) => !['boss', 'elite_boss'].includes(e.ev.type)).length;
    lanes.events.label.querySelector('.lane-sub').textContent = plural(evs.length, 'event') + (olds ? ` · ${olds} old (convert: Save)` : '');
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
    const key = 'paths';
    const g = svg('g', { class: 'paths' + (App.selKey() === key ? ' selected' : '') + issueClass(key), 'data-key': key, onpointerdown: (e) => { if (e.button === 0) { e.stopPropagation(); App.select({ kind: 'paths' }); } } });
    g.appendChild(svg('rect', { x: 0, y: 0, width: w, height: PATH_H, class: 'paths-hit' }));
    let n = 0;
    for (let st = 0; st < App.stages() && pt.length; st++) {
      const list = pt[Math.min(st, pt.length - 1)] || [];
      list.forEach((v, k) => {
        const px = x(App.stageStart(st) + Number(v));
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
      p0: spec.kind === 'cap' ? pair(tl.cap_curve[spec.k]) : spec.kind === 'floor' ? pair(tl.floor_curve[spec.k]) : spec.kind === 'curve' ? pair(tl[spec.key].points[spec.k]) : spec.kind === 'weight' ? pair(item.weights[spec.k]) : null,
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
    if (sp.kind === 'cap' || sp.kind === 'curve' || sp.kind === 'floor') {
      const p = sp.kind === 'cap' ? tl.cap_curve[sp.k] : sp.kind === 'floor' ? tl.floor_curve[sp.k] : tl[sp.key].points[sp.k];
      const raw = Math.max(0, drag.p0[0] + dt);
      const sn = snapTo([{ t: raw, edge: 'point', min: 0 }]);
      p[0] = sn ? sn.t : raw;
      const dv = -((e.clientY - drag.y0) / (sp.bottom - sp.top)) * sp.maxV;
      p[1] = sp.kind === 'cap' || sp.kind === 'floor' ? Math.max(0, Math.round(drag.p0[1] + dv)) : Math.max(0, Model.round(drag.p0[1] + dv, 2));
      render();
      showSnap(sn, e);
      App.setClock(p[0], (sp.kind === 'cap' ? `cap ${p[1]}` : sp.kind === 'floor' ? `floor ${p[1]} alive` : `×${p[1]}`) + snapText(sn));
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
    const sel = sp.kind === 'cap' ? { kind: 'cap' } : sp.kind === 'floor' ? { kind: 'floor' } : sp.kind === 'curve' ? { kind: sp.lane } : sp.kind === 'weight' ? { kind: 'roster', i: sp.i } : { kind: sp.kind, i: sp.i };
    if (d.moved) {
      const tl = App.tl();
      if (sp.kind === 'cap') App.sortPoints(tl.cap_curve);
      if (sp.kind === 'floor') App.sortPoints(tl.floor_curve);
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
    const box = el('div', {}, cardHead(r.name ? `Spawn row: ${r.name}` : 'Spawn row', t, `${fmtT(r.t)} → ${r.until == null || r.until === '' ? 'end' : fmtT(r.until)}${r.id ? ` · ${r.id}` : ''}`));
    // pass 84 (lane TIMELINE): how many, how often, who and what it wears, in one line; the creature (the first of a list)
    const c84 = App.creature(firstEnemy(r));
    const pace84 = TimelineModel.paceOf(r);
    const flags84 = [r.elite ? `every one wears ${r.elite === 'random' ? 'a random elite modifier' : r.elite}` : '', r.special ? 'every one its coloured special' : '', r.banner ? `banner "${r.banner}"` : '', r.channel === 'hell' ? 'hell channel' : '', r.respect_cap === false && pace84 !== 'continuous' ? 'on top of the cap' : '', TimelineModel.roleOf(r) ? `role ${TimelineModel.roleOf(r)}` : ''].filter(Boolean);
    box.appendChild(el('div', { class: 'hc-line' }, el('b', { text: TimelineModel.quantityText(r, Model.rowWaveCount(r, c84), pace84 === 'continuous' ? perMinute(i, r) : null) }), ` · ${enemyWords(r)}${Array.isArray(r.enemy) && r.enemy.length > 1 ? ` (one of ${r.enemy.map((id) => App.creatureName(id)).join(', ')})` : ''}${flags84.length ? ' · ' + flags84.join(' · ') : ''}`));
    if (r.enemy === 'roster') box.appendChild(el('div', { class: 'hc-line muted', text: 'each creature drawn from the rows open then by their Elite weight, with that row\'s HP and ATK' }));
    else box.appendChild(creatureBlock(firstEnemy(r), r.variant, r.stats, t, { t0: Number(r.t) || 0, from: 'row', modded: !!r.elite, forced: !!r.special }));
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

  let lastCursorT = null;             // pass 84: the second under the pointer last (the inspector's Split at cursor)
  function onHover(e) {
    if (drag || pan || !App.S.map) return;
    const t = tAt(e.clientX);
    if (t < 0 || e.clientX < svgLeft()) { hideCursor(); return; }
    lastCursorT = Math.max(0, Math.round(t));
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

  return { mount, render, fit, zoom, viewCenter, scrollToSelection, hideCard, LABEL_W, ALT_COLORS, get spp() { return spp; }, setSnap, toggleSnap, get snapOn() { return snapOn; }, setWindow, get winSecs() { return winSecs; },
    // pass 84 (lane TIMELINE): the cursor's last second (split at cursor), the sections, the Sim overlay, the warnings
    get cursorT() { return lastCursorT; }, isCollapsed, setCollapsed, setAll, loadSimList, warningsOf, get view() { return view; }, get sim() { return simOv; },
    rowSpawnsPerSecond, firstEnemy, enemyWords, startNumbers,
    // pass 85 (lane TOOLS): the right-button pan of the Spawn rows
    panTo, get panning() { return !!pan; } };
})();
