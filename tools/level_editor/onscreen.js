'use strict';
// Pass 133 (lane ONSCREEN): "Show on screen", the Timeline tab's pop-up that draws the crowd the On screen estimate
// expects at one second: the outlaw in the middle, every expected body round him as its look's strip (its row's size and
// look, an Elite's crown, a special's rim, the stage's filter over all), laid out as OnScreenModel.layout does it
// (onscreen_model.js: the spawn pattern, the walk in, the push apart), every figure playing run, run turned, die, 2 s
// each on one clock. Nothing is counted here and nothing is saved: the numbers are the estimate's point at the chosen
// second (model.js spawnEstimate / estimateAt), the strips the server's (/sprite/<kind>/<id>/<code>), the layout re-laid
// from a seed ("Re-roll" draws the fractions again).
//
// Drawing: one canvas, one requestAnimationFrame while the pop-up is open, cells blitted straight from the loaded strip
// images (no StripPlayer per body: a crowd of 300 at a full cap). A stage filter tints each strip once, on an offscreen
// canvas (multiply, the alpha put back), so a frame is plain drawImage calls. The view is the game's from above-behind:
// x across at ppm px/m, ground depth at ppm x DEPTH, billboards upright on their feet, sorted by depth.
const OnScreen = (() => {
  const el = (...a) => U.el(...a);
  const O = OnScreenModel;
  const W = 560, H = 900;
  /** The game's view at zoom 1: 12 m across the phone's width (the camera's 90 px/m on 1080 px). */
  const VIEW_W_M = 12;
  const ZOOMS = [1, 1.5, 2, 3];
  const HERO_FALLBACK = 'drifter';
  const SAND = [0.78, 0.64, 0.42];

  let dlg = null;            // the open pop-up's state
  let heroes = null;         // /api/heroes once

  // ------------------------------------------------------------------ the strips

  /** The look record a body plays: a creature's `variants` entry by code (else its played one), with the strip's keys. */
  function creatureLook(c, code) {
    if (!c) return null;
    const vs = Array.isArray(c.variants) ? c.variants : [];
    let v = code ? vs.find((x) => x && x.code === code) : null;
    if (!v) v = vs.find((x) => x && x.default) || vs.find((x) => x && x.base) || vs[0] || null;
    if (!v) return { key: 'enemy|' + c.id + '|', url: c.sprite_play || c.sprite, anims: c.anims || {}, fps: c.fps || {}, cols: c.strip_cols || 0, px: c.frame_px || 128, front: c.front_faces, back: c.back_faces, kind: 'enemy', eight: !!(c.anims && c.anims.run_s > 0) };
    const anims = v.anims || c.anims || {};
    return { key: 'enemy|' + c.id + '|' + v.code, url: v.sprite, anims, fps: v.fps || c.fps || {}, cols: v.strip_cols || 0, px: v.frame_px || c.frame_px || 128, front: v.front_faces, back: v.back_faces, kind: 'enemy', eight: !!(anims.run_s > 0), code: v.code };
  }
  function heroLook(h) {
    if (!h) return null;
    const looks = Array.isArray(h.looks) ? h.looks : [];
    const v = looks.find((x) => x && x.default) || looks.find((x) => x && x.base) || looks[0] || null;
    const anims = v && v.anims ? v.anims : (h.anims || {});
    return { key: 'hero|' + h.id + '|' + (v ? v.code : ''), url: v ? v.sprite : h.sprite, anims, fps: v && v.fps ? v.fps : (h.fps || {}), cols: v ? v.strip_cols : h.strip_cols || 0, px: v && v.frame_px ? v.frame_px : h.frame_px || 256, kind: 'hero', eight: true, code: v ? v.code : '' };
  }

  /** Load the strips the scene needs (cached on the pop-up), each tinted once for the stage filter. */
  function loadStrips(state, looks) {
    const mults = state.filter.actors;
    const tinted = state.filter.on;
    const jobs = [];
    for (const lk of looks) {
      if (!lk || state.strips.has(lk.key)) continue;
      const entry = { img: null, ready: false, failed: false, w: 0, h: 0 };
      state.strips.set(lk.key, entry);
      jobs.push(new Promise((resolve) => {
        const img = new Image();
        img.onload = () => {
          entry.w = img.naturalWidth; entry.h = img.naturalHeight;
          entry.img = tinted ? tintStrip(img, mults) : img;
          entry.ready = true; resolve();
        };
        img.onerror = () => { entry.failed = true; resolve(); };
        img.src = lk.url;
      }));
    }
    return Promise.all(jobs);
  }
  /** The strip multiplied by the filter's creature factor (StageLook: white.lerp(color, strength x actors)), alpha kept. */
  function tintStrip(img, m) {
    try {
      const c = document.createElement('canvas');
      c.width = img.naturalWidth; c.height = img.naturalHeight;
      const g = c.getContext('2d');
      g.drawImage(img, 0, 0);
      g.globalCompositeOperation = 'multiply';
      g.fillStyle = `rgb(${Math.round(m[0] * 255)},${Math.round(m[1] * 255)},${Math.round(m[2] * 255)})`;
      g.fillRect(0, 0, c.width, c.height);
      g.globalCompositeOperation = 'destination-in';
      g.drawImage(img, 0, 0);
      return c;
    } catch (_) { return img; }
  }

  // ------------------------------------------------------------------ the estimate at a second

  /** The stage run's estimate for stage s (the Timeline's assumptions) and its window. */
  function estimateFor(s) {
    const w = App.stageWindow(s);
    // the Timeline's assumptions, the run clock to this stage's window (the page's `end` is the open tab's)
    const opts = Object.assign({}, App.spawnOpts(), { stage: s, end: w.end + App.portalSeconds() });
    const est = Model.spawnEstimate(App.tl(), App.S.enemies, opts);
    return { est, w, opts };
  }
  /** The kill rate as one number at map second t of stage s (the estimate's turnover: a number, per stage, or a curve). */
  function turnoverAt(opts, t, s, w) {
    const tv = opts.turnover;
    if (typeof TimelineModel !== 'undefined' && typeof TimelineModel.turnoverAt === 'function') {
      try { return TimelineModel.turnoverAt(tv, Array.isArray(tv) && tv.length && Array.isArray(tv[0]) ? t - w.start : t, s); } catch (_) { /* below */ }
    }
    return typeof tv === 'number' ? tv : O.TURNOVER_DEF;
  }
  /** The peak second of a stage window in the estimate (bodies alive). */
  function peakSecond(est, w) {
    let best = null;
    for (const p of est.points) if (!p.after && p.t >= w.start && p.t <= w.end && (!best || p.alive > best.alive)) best = p;
    return best ? best.t : w.start;
  }

  /** The hero the scene shows: the Sim tab's pick (its form, else the browser's copy of it), else the Drifter. */
  function heroId() {
    try { if (typeof Sim !== 'undefined' && Sim.S && Sim.S.form && Sim.S.form.hero) return String(Sim.S.form.hero); } catch (_) { /* none */ }
    try { const f = JSON.parse(localStorage.getItem('88fits-sim-form') || 'null'); if (f && f.hero) return String(f.hero); } catch (_) { /* none */ }
    return HERO_FALLBACK;
  }

  // ------------------------------------------------------------------ the pop-up

  /** Open the pop-up on stage `s` (default: the Timeline's stage tab, else the first) at second `t` (map seconds; default
   *  the Timeline's cursor inside the window, else the stage's peak). */
  async function open(s, t) {
    if (!App.S.map) return;
    close();
    const stage = s != null ? s : (App.viewStage() != null ? App.viewStage() : 0);
    const state = { stage, t: 0, seed: 1, zoom: 2, strips: new Map(), layout: null, raf: 0, t0: 0, est: null, w: null, opts: null, filter: O.filterMults(null), hero: null, heroLook: null, busy: 'loading…', dead: false };
    dlg = state;
    const back = el('div', { class: 'amodal-back onscreen-back' });
    const box = el('div', { class: 'amodal wide onscreen' });
    back.appendChild(box);
    state.back = back; state.box = box;
    const onKey = (e) => {
      if (!document.body.contains(back)) return;
      if (e.key === 'Escape') { e.preventDefault(); e.stopImmediatePropagation(); close(); }
      else if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') { if (e.target && e.target.tagName === 'INPUT') return; e.preventDefault(); setTime(state.t + (e.key === 'ArrowLeft' ? -1 : 1)); }
      else if (String(e.key).toLowerCase() === 'r' && !e.ctrlKey && !e.metaKey) { if (e.target && e.target.tagName === 'INPUT') return; reroll(); }
    };
    state.onKey = onKey;
    document.addEventListener('keydown', onKey, true);
    back.addEventListener('mousedown', (e) => { if (e.target === back) close(); });
    document.body.appendChild(back);
    buildShell(state);
    if (!heroes) { try { heroes = await (await fetch('/api/heroes', { cache: 'no-store' })).json(); } catch (_) { heroes = []; } }
    if (state.dead) return;
    const hid = heroId();
    state.hero = (heroes || []).find((h) => h.id === hid) || (heroes || []).find((h) => h.id === HERO_FALLBACK) || (heroes || [])[0] || null;
    state.heroLook = heroLook(state.hero);
    setStage(state, stage, t);
  }

  function close() {
    if (!dlg) return;
    const s = dlg;
    dlg = null;
    s.dead = true;
    if (s.raf) cancelAnimationFrame(s.raf);
    document.removeEventListener('keydown', s.onKey, true);
    if (s.back) s.back.remove();
    s.strips.clear();
  }

  /** The window's furniture: the title, the controls, the canvas, the numbers. */
  function buildShell(state) {
    const box = state.box;
    box.appendChild(el('h3', { text: "What's on screen at second t" }));
    box.appendChild(el('p', { class: 'muted small onscreen-note', text: 'The crowd the On screen estimate expects at this second of the stage, laid out round the Outlaw as the rows spawn it (the fresh ones far out, the old ones close in, a ring row on its ring, nothing overlapping). Each body wears its row\'s look and size, a crown for an Elite modifier or an Elite boss, a rim for a special, the stage\'s filter over all. Fractions are rolled (Re-roll draws them again). Every figure plays run, run turned, die, 2 s each.' }));
    const ctl = el('div', { class: 'onscreen-ctl' });
    // the stage
    state.stageSel = el('select', { class: 'onscreen-stage', title: 'the stage whose run the estimate plays (a fresh Outlaw from its start)' });
    for (let k = 0; k < App.stages(); k++) state.stageSel.appendChild(el('option', { value: String(k), text: `${k + 1}. ${App.stageWindow(k).name}` }));
    state.stageSel.addEventListener('change', () => setStage(state, Number(state.stageSel.value), null));
    ctl.appendChild(el('label', { class: 'onscreen-field' }, el('span', { class: 'muted small', text: 'Stage' }), state.stageSel));
    // the second
    const minus = el('button', { class: 'btn small', type: 'button', text: '−1 s', title: 'one second earlier (left arrow)', onclick: () => setTime(state.t - 1) });
    const plus = el('button', { class: 'btn small', type: 'button', text: '+1 s', title: 'one second later (right arrow)', onclick: () => setTime(state.t + 1) });
    state.slider = el('input', { type: 'range', class: 'onscreen-slider', min: 0, max: 100, step: 1, value: 0, title: 'the second of the stage (its own clock, as the Timeline\'s stage tab counts it)' });
    state.slider.addEventListener('input', () => setTime(state.w.start + Number(state.slider.value)));
    state.timeEl = el('b', { class: 'onscreen-time', text: '0:00' });
    ctl.appendChild(el('span', { class: 'onscreen-field onscreen-timebox' }, minus, state.slider, plus, state.timeEl));
    const peak = el('button', { class: 'btn small', type: 'button', text: 'Peak', title: 'jump to the second with the most bodies alive in this stage', onclick: () => setTime(peakSecond(state.est, state.w)) });
    ctl.appendChild(peak);
    // the roll and the zoom
    ctl.appendChild(el('button', { class: 'btn small', type: 'button', text: 'Re-roll', title: 'draw the fractions and the places again from a new seed (R)', onclick: reroll }));
    state.zoomSel = el('select', { class: 'onscreen-zoom', title: 'how far out the view is: 1 = the phone\'s own 12 m across at the start of a run (the camera pulls out as the Outlaw levels and sprints, to about 2)' });
    for (const z of ZOOMS) state.zoomSel.appendChild(el('option', { value: String(z), text: `zoom ${z}×`, selected: z === state.zoom }));
    state.zoomSel.addEventListener('change', () => { state.zoom = Number(state.zoomSel.value) || 2; });
    ctl.appendChild(state.zoomSel);
    ctl.appendChild(el('button', { class: 'btn small', type: 'button', text: 'Close', title: 'close (Escape)', onclick: close }));
    box.appendChild(ctl);
    const row = el('div', { class: 'onscreen-row' });
    state.canvas = el('canvas', { class: 'onscreen-canvas', width: W, height: H });
    row.appendChild(el('div', { class: 'onscreen-stage-box' }, state.canvas));
    state.side = el('div', { class: 'onscreen-side' });
    row.appendChild(state.side);
    box.appendChild(row);
    state.seedEl = el('span', { class: 'muted small' });
  }

  function setStage(state, s, t) {
    state.stage = s;
    state.stageSel.value = String(s);
    const r = estimateFor(s);
    state.est = r.est; state.w = r.w; state.opts = r.opts;
    const entry = App.stageList()[s] ? App.stageList()[s].entry : null;
    state.filter = O.filterMults(entry && entry.filter);
    state.filterEntry = entry && entry.filter ? entry.filter : null;
    state.strips.clear();   // the tint changes with the stage
    state.slider.min = 0; state.slider.max = Math.max(1, Math.round(state.w.length));
    let want = t != null && t >= state.w.start && t <= state.w.end ? t : null;
    if (want == null) { const c = typeof Timeline !== 'undefined' ? Timeline.cursorT : null; want = c != null && c >= state.w.start && c <= state.w.end ? c : peakSecond(state.est, state.w); }
    setTime(want);
  }

  /** The second (map seconds): the estimate's point there, the layout, the strips, the numbers. */
  function setTime(t) {
    const state = dlg;
    if (!state || !state.w) return;
    const tt = Math.max(state.w.start, Math.min(state.w.end, Math.round(Number(t) || 0)));
    state.t = tt;
    state.slider.value = String(tt - state.w.start);
    state.timeEl.textContent = `${U.fmtT(tt - state.w.start)} of ${U.fmtT(state.w.length)}`;
    state.timeEl.title = `map ${U.fmtT(tt)}`;
    relay(state);
  }

  function reroll() {
    const state = dlg;
    if (!state) return;
    state.seed = (state.seed * 1103515245 + 12345) % 2147483647 || 7;
    relay(state);
  }

  /** The layout for the second and seed in hand, then the strips it needs (drawn as they land). */
  function relay(state) {
    const p = Model.estimateAt(state.est, state.t);
    const before = Model.estimateAt(state.est, state.t - O.ATTRIB_WINDOW);
    const tl = App.tl();
    const spd = Model.speedOf(tl, { speed: 1 }, {}, state.t);
    const L = O.layout(p, before, tl.roster || [], App.S.byId, { seed: state.seed + state.t * 131, turnover: turnoverAt(state.opts, state.t, state.stage, state.w),
      sides: tl.spawn_sides, specialDefaults: tl.special_defaults, speedMult: spd.spd > 0 ? spd.spd : 1, maxBodies: Model.MAX_BODIES });
    state.point = p;
    state.layout = L;
    // the looks the scene needs
    const looks = [];
    for (const b of L.bodies) { b.lk = creatureLook(App.creature(b.id), b.look); if (b.lk) looks.push(b.lk); }
    if (state.heroLook) looks.push(state.heroLook);
    L.bodies.sort((a, b) => a.z - b.z || a.x - b.x);
    state.busy = looks.some((lk) => !state.strips.has(lk.key)) ? 'loading the strips…' : '';
    renderSide(state);
    loadStrips(state, looks).then(() => { if (dlg === state) { state.busy = ''; renderSide(state); } });
    if (!state.raf) { state.t0 = performance.now(); state.raf = requestAnimationFrame(frame); }
  }

  /** The numbers beside the scene: the total, the cap, the breakdown by creature. */
  function renderSide(state) {
    const side = state.side;
    U.clear(side);
    const L = state.layout, p = state.point || {};
    if (!L) return;
    const alive = Number(p.alive) || 0;
    side.appendChild(el('div', { class: 'onscreen-head' }, el('b', { text: `On screen ≈ ${U.fmtN(alive, 1)}` }), el('span', { class: 'muted small', text: ` · drawn ${L.total}` })));
    side.appendChild(el('div', { class: 'small', text: `cap ${p.cap != null ? p.cap : '–'} load · hard cap ${Model.MAX_BODIES} bodies (the pool)${p.full > 0 ? ` · cap full ${Math.round(p.full * 100)}% of the checks` : ''}` }));
    side.appendChild(el('div', { class: 'muted small', text: `Stage ${state.stage + 1}, ${state.w.name} · ${U.fmtT(state.t - state.w.start)} (map ${U.fmtT(state.t)}) · seed ${state.seed}${state.busy ? ' · ' + state.busy : ''}` }));
    side.appendChild(el('div', { class: 'muted small onscreen-filter', text: state.filter.on ? `filter ${state.filterEntry.color} at ${Math.round((Number(state.filterEntry.strength) || 0) * 100)}% (creatures ${Math.round((Number(state.filterEntry.strength) || 0) * (state.filterEntry.actors != null ? Number(state.filterEntry.actors) : O.ACTORS_DEFAULT) * 100)}%)` : 'no stage filter (daylight)' }));
    state.phaseEl = el('div', { class: 'muted small onscreen-phase' });
    side.appendChild(state.phaseEl);
    const list = el('div', { class: 'onscreen-list' });
    list.appendChild(el('div', { class: 'onscreen-li onscreen-hdr' }, el('span'), el('span', { text: 'creature' }), el('span', { text: 'drawn' }), el('span', { text: 'expected' }), el('span', { text: 'Elite' }), el('span', { text: 'special' })));
    for (const c of L.counts) {
      const cr = App.creature(c.id);
      list.appendChild(el('div', { class: 'onscreen-li' + (c.n ? '' : ' zero'), title: `${c.id}: the estimate expects ${U.fmtN(c.expected, 2)} alive; ${c.n} drawn (the whole part, one more with the fraction as the chance)` },
        cr ? el('img', { src: App.iconFor(c.id), width: 18, height: 18 }) : el('span'),
        el('span', { class: 'onscreen-name', text: cr ? cr.name : c.id }),
        el('span', { text: String(c.n) }), el('span', { class: 'muted', text: U.fmtN(c.expected, 1) }),
        el('span', { text: c.elite ? String(c.elite) : '' }), el('span', { text: c.special ? String(c.special) : '' })));
    }
    if (!L.counts.length) list.appendChild(el('div', { class: 'muted small', text: 'nobody is alive at this second in the estimate' }));
    side.appendChild(list);
    const failed = [...state.strips.values()].filter((e) => e.failed).length;
    if (failed) side.appendChild(el('div', { class: 'small bad', text: `${failed} strip${failed === 1 ? '' : 's'} could not be loaded (drawn as a disc)` }));
    side.appendChild(el('p', { class: 'muted small onscreen-foot', text: 'Keys: ← → one second, R re-roll, Escape close. The dashed ring is a ring row\'s 11.7 m, the dashed band where regular spawns land (19–24 m), the frame the phone\'s own 12 m view at the start of a run.' }));
  }

  // ------------------------------------------------------------------ the draw

  function frame(now) {
    const state = dlg;
    if (!state) return;
    state.raf = requestAnimationFrame(frame);
    const secs = (now - state.t0) / 1000;
    const ph = O.phaseAt(secs);
    if (state.phaseEl && state.lastPhase !== ph.k) { state.lastPhase = ph.k; state.phaseEl.textContent = `playing: ${ph.phase.label} (${ph.k + 1} of ${O.PHASES.length}, ${O.PHASE_SECONDS} s each)`; }
    draw(state, ph);
  }

  function draw(state, ph) {
    const g = state.canvas.getContext('2d');
    const zoom = state.zoom || 2;
    const ppm = W / (VIEW_W_M * zoom);
    const cx = W / 2, cy = H * 0.58;
    const L = state.layout;
    // the ground under the filter
    const wm = state.filter.world;
    g.fillStyle = `rgb(${Math.round(SAND[0] * wm[0] * 255)},${Math.round(SAND[1] * wm[1] * 255)},${Math.round(SAND[2] * wm[2] * 255)})`;
    g.fillRect(0, 0, W, H);
    // the guides: the ring, the spawn band, the phone's view at zoom 1
    g.save();
    g.strokeStyle = 'rgba(0,0,0,0.22)'; g.lineWidth = 1; g.setLineDash([4, 6]);
    const ell = (R) => { g.beginPath(); g.ellipse(cx, cy, R * ppm, R * ppm * O.DEPTH, 0, 0, Math.PI * 2); g.stroke(); };
    ell(O.RING_RADIUS); ell(O.SPAWN_NEAR); ell(O.SPAWN_FAR);
    if (zoom > 1) { const fw = VIEW_W_M * ppm, fh = H / zoom; g.strokeStyle = 'rgba(255,255,255,0.35)'; g.setLineDash([6, 4]); g.strokeRect(cx - fw / 2, cy - fh * 0.58, fw, fh); }
    g.restore();
    if (!L) return;
    // the shadows first
    g.fillStyle = 'rgba(0,0,0,0.22)';
    for (const b of L.bodies) { const s = O.project(b.x, b.z, ppm, cx, cy); g.beginPath(); g.ellipse(s.sx, s.sy, Math.max(2, b.radius * ppm), Math.max(1.2, b.radius * ppm * O.DEPTH), 0, 0, Math.PI * 2); g.fill(); }
    g.beginPath(); g.ellipse(cx, cy, O.HERO_RADIUS * ppm, O.HERO_RADIUS * ppm * O.DEPTH, 0, 0, Math.PI * 2); g.fill();
    // the bodies back to front, the outlaw among them at his depth
    let heroDrawn = false;
    for (const b of L.bodies) {
      if (!heroDrawn && b.z > 0) { drawHero(g, state, ph, ppm, cx, cy); heroDrawn = true; }
      drawBody(g, state, b, ph, ppm, cx, cy);
    }
    if (!heroDrawn) drawHero(g, state, ph, ppm, cx, cy);
  }

  /** A strip cell on its feet: {img, sx, sy, fp, mirror, hold} for the phase's frame, or null (no strip). */
  function cellOf(state, lk, kind, anim, dir, facing, ph) {
    const entry = state.strips.get(lk.key);
    if (!entry || !entry.ready || !entry.img) return null;
    const ak = StripPlayer.animKey(kind, lk.anims, anim, dir, facing);
    if (!ak.ok) return null;
    const count = Number(lk.anims[ak.key]) || 0;
    if (count <= 0) return null;
    const fps = StripPlayer.previewFps(kind, ak.key, lk.fps);
    const raw = Math.floor(ph.into * fps);
    const k = anim === 'die' ? Math.min(raw, count - 1) : raw % count;
    const off = StripPlayer.frameOffset(lk.anims, ak.key, StripPlayer.order(kind));
    const cols = lk.cols > 0 ? lk.cols : Math.floor(entry.w / lk.px) || 1;
    const [x, y] = StripPlayer.cell(off + k, cols, lk.px);
    if (y + lk.px > entry.h + 0.5 || x + lk.px > entry.w + 0.5) return null;
    return { img: entry.img, sx: x, sy: y, fp: lk.px, mirror: StripPlayer.mirror(kind, ak.view, facing, lk.front, lk.back, lk.anims) };
  }

  function drawBody(g, state, b, ph, ppm, cx, cy) {
    const s = O.project(b.x, b.z, ppm, cx, cy);
    const hpx = Math.max(6, b.size * ppm);
    const f = O.facingOf(b.x, b.z, !!(b.lk && b.lk.eight), ph.phase.turned);
    const c = b.lk ? cellOf(state, b.lk, 'enemy', ph.phase.anim, f.dir, f.facing, ph) : null;
    const dx = s.sx - hpx / 2, dy = s.sy - hpx;
    if (!c) {
      // no strip (yet): a disc in the creature's colour
      g.fillStyle = App.creatureColor(b.id);
      g.beginPath(); g.arc(s.sx, s.sy - hpx * 0.45, Math.max(3, hpx * 0.3), 0, Math.PI * 2); g.fill();
    } else {
      if (b.special) drawRim(g, state, c, dx, dy, hpx, b.tint, b.glow);
      blit(g, c, dx, dy, hpx);
    }
    if (b.crown) drawCrown(g, s.sx, dy - 2, Math.max(8, hpx * 0.28));
  }

  function drawHero(g, state, ph, ppm, cx, cy) {
    const lk = state.heroLook;
    const hpx = O.HERO_SIZE * ppm;
    const dir = ph.phase.anim === 'die' ? '' : ph.phase.turned ? 'front' : 'back';
    const c = lk ? cellOf(state, lk, 'hero', ph.phase.anim, dir, 'right', ph) : null;
    if (!c) { g.fillStyle = '#f0e6c8'; g.beginPath(); g.arc(cx, cy - hpx * 0.45, hpx * 0.25, 0, Math.PI * 2); g.fill(); return; }
    blit(g, c, cx - hpx / 2, cy - hpx, hpx);
  }

  function blit(g, c, dx, dy, size) {
    if (!c.mirror) { g.drawImage(c.img, c.sx, c.sy, c.fp, c.fp, dx, dy, size, size); return; }
    g.save(); g.translate(dx + size, dy); g.scale(-1, 1); g.drawImage(c.img, c.sx, c.sy, c.fp, c.fp, 0, 0, size, size); g.restore();
  }

  /** A special's glowing rim: the cell's silhouette in its tint, drawn a little bigger round the body (the shader's
   *  emissive rim, 1 + 4.2 x glow px wide, breathing). */
  function drawRim(g, state, c, dx, dy, size, tint, glow) {
    if (!state.rimCanvas) { state.rimCanvas = document.createElement('canvas'); }
    const rc = state.rimCanvas;
    if (rc.width !== c.fp || rc.height !== c.fp) { rc.width = c.fp; rc.height = c.fp; }
    const rg = rc.getContext('2d');
    rg.clearRect(0, 0, c.fp, c.fp);
    rg.globalCompositeOperation = 'source-over';
    rg.drawImage(c.img, c.sx, c.sy, c.fp, c.fp, 0, 0, c.fp, c.fp);
    rg.globalCompositeOperation = 'source-in';
    rg.fillStyle = tint || '#8A1428';
    rg.fillRect(0, 0, c.fp, c.fp);
    const breathe = 0.8 + 0.2 * (0.5 + 0.5 * Math.sin(performance.now() / 320));
    const w = (1 + 4.2 * (glow || 0.6)) * breathe * (size / 96);
    g.save();
    g.globalAlpha = 0.85;
    for (let k = 0; k < 8; k++) {
      const a = (k / 8) * Math.PI * 2;
      const ox = Math.cos(a) * w, oy = Math.sin(a) * w;
      if (!c.mirror) g.drawImage(rc, dx + ox, dy + oy, size, size);
      else { g.save(); g.translate(dx + size + ox, dy + oy); g.scale(-1, 1); g.drawImage(rc, 0, 0, size, size); g.restore(); }
    }
    g.restore();
  }

  /** An Elite's crown above the head (the game's crown badge): three gold points on a band. */
  function drawCrown(g, x, y, w) {
    const h = w * 0.6;
    g.save();
    g.fillStyle = '#f2c230'; g.strokeStyle = '#6a4a08'; g.lineWidth = 1;
    g.beginPath();
    g.moveTo(x - w / 2, y); g.lineTo(x - w / 2, y - h * 0.9); g.lineTo(x - w / 4, y - h * 0.45); g.lineTo(x, y - h); g.lineTo(x + w / 4, y - h * 0.45); g.lineTo(x + w / 2, y - h * 0.9); g.lineTo(x + w / 2, y);
    g.closePath(); g.fill(); g.stroke();
    g.restore();
  }

  return { open, close, creatureLook, heroLook, heroId, peakSecond, get state() { return dlg; } };
})();
