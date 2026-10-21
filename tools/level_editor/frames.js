// The Frames view (pass 95, lane VACE). Garry: "a way to view every single frame and choose which ones to regenerate
// ... available to existing assets too ... options per frame (the history of other generated frames) ... frames from
// other Looks ... several frame changes in one go without needing to wait for the save export". Three parts:
//
//   Frames.open(kind, id, code, o)   the view, a <dialog>: one animation x view at a time (tabs with their staged
//                                    counts), the effective frame big with its slot number and badges, the previous and
//                                    next frames beside it, the driver's frame under it, play / pause / step / scrub /
//                                    speed / loop / zoom, every frame as a numbered sheet (click = show, shift-click =
//                                    a range, ctrl-click = toggle), the versions of the shown slot (click = stage, pin,
//                                    unstage), the actions: Repair with VACE (a job), From another look, Ask the local
//                                    vision model, Undo (unstage), Export (one job for the whole look).
//   Frames.summary(kind, id, code)   GET /api/frames/<kind>/<id>/<code> (the groups), used by the cards' badges.
//
// Every choice is one POST to the store (tools/level_editor/frames_io.py) and is staged at once: the preview plays it,
// a reload shows it again, nothing in the game changes until Export. While a repair job of the look runs the group is
// fetched again every few seconds, so its new versions appear (and are staged) as they land. The maths live in
// frames_model.js (FramesModel), checked under Node by selftest_VACE95.py.
'use strict';

const Frames = (() => {
  const FM = FramesModel;
  const el = (...a) => U.el(...a);
  const CELL = 160;
  const HELP = 'Every frame of the animation is a slot; every slot keeps every version it ever had, named SP-B / Run / Side / Frame 07 / v1 (the installed frame), v2 (the first repair of it), ... No version is ever deleted. '
    + 'A click on a version stages it: the preview plays it at once and nothing is written until Export packs the strip. A pinned slot keeps its choice when a job re-rolls the look: the landing packs the pinned frames back into the strip ("re-applied N pinned frames" on the card). '
    + 'Every Export that replaces an installed strip shows one box listing the whole batch (each changed frame before and after, the flags it raises or clears); one click approves all of it. '
    + 'Repair with VACE paints the chosen frames anew with Wan 2.2 Fun VACE, the other frames kept and the driver\'s frame as the guide; the new frames land here as versions, staged. '
    + 'The flags are deterministic hints (a jump from both neighbours, a footprint off the median, an empty frame, a loop seam, a silhouette unlike the driver\'s): they miss ghost legs and faces on backs, so look. '
    + 'Each method has a repair rule (methods.json): VACE runs where a clip or a driver exists; a procedural animation (an idle, an attack, a hit, a hop walk) is refused unless you tick "fill freely anyway", because the still is the thing to fix there. '
    + 'A repair job\'s new frames are staged when it lands (unless the slot is pinned or you staged a choice meanwhile). A failed merge or import puts the old strip back and stages your frames again. '
    + 'Where frames live: the strip under game/content/ (what the game plays), the clip cache under tools/dl/ai_anim/ (what the video model painted), every version under tools/dl/frames/, the old strip of every export under tools/level_editor/backups/<id>/ (the newest 30 kept).';

  async function fetchJson(url, dflt) {
    try { const r = await fetch(url, { cache: 'no-store' }); if (!r.ok) return dflt; return await r.json(); } catch (_) { return dflt; }
  }
  async function post(url, body) {
    try {
      const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) });
      const j = await r.json().catch(() => ({}));
      if (!r.ok && !j.error) j.error = `HTTP ${r.status}`;
      return j;
    } catch (e) { return { ok: false, error: String(e) }; }
  }
  const status = (msg, tone, detail) => { if (typeof App !== 'undefined' && App.status) App.status(msg, tone, detail); };
  const base = (kind, id, code) => `/api/frames/${encodeURIComponent(kind)}/${encodeURIComponent(id)}/${encodeURIComponent(code)}`;

  function summary(kind, id, code) { return fetchJson(base(kind, id, code), null); }

  /** The view on a look. o: {base, view, slot}. */
  async function open(kind, id, code, opts) {
    const o = opts || {};
    const dlg = document.createElement('dialog');
    dlg.className = 'sp-modal fr-modal';
    dlg.appendChild(el('div', { class: 'sp-modal-head' }, el('b', { text: `Frames · ${id} · ${code}` }), el('span', { class: 'muted small', text: 'loading…' }), el('span', { class: 'spacer' }), el('button', { type: 'button', class: 'btn small', text: '✕', onclick: () => dlg.close() })));
    document.body.appendChild(dlg);
    let viewer = null;
    dlg.addEventListener('close', () => { if (viewer) viewer.stop(); dlg.remove(); });
    dlg.showModal();
    const sum = await summary(kind, id, code);
    if (!dlg.isConnected) return null;
    if (!sum || !sum.ok || !sum.groups || !sum.groups.length) {
      U.clear(dlg);
      dlg.append(el('div', { class: 'sp-modal-head' }, el('b', { text: `Frames · ${id} · ${code}` }), el('span', { class: 'spacer' }), el('button', { type: 'button', class: 'btn small', text: '✕', onclick: () => dlg.close() })),
        el('p', { class: 'warn-text', text: sum && sum.error ? sum.error : `${code} has no frames: no strip is installed for it (a draft, a stub, or a server older than pass 95).` }), el('p', { class: 'muted small', text: HELP }));
      return null;
    }
    viewer = new Viewer(dlg, kind, id, code, sum, o);
    await viewer.show(o.base, o.view, o.slot);
    return viewer;
  }

  class Viewer {
    constructor(dlg, kind, id, code, sum, o) {
      this.dlg = dlg; this.kind = kind; this.id = id; this.code = code; this.sum = sum; this.o = o || {};
      this.detail = null; this.base = null; this.view = null;
      this.slot = 0; this.sel = new Set(); this.anchor = null;
      this.playing = false; this.pos = 0; this.fps = 10; this.loop = true; this.zoom = 2;
      this.raf = 0; this.last = 0; this.acc = 0; this.preload = [];
      this.others = null; this.pollTimer = 0; this.busy = false; this.panel = null;
      this.build();
      this.dlg.addEventListener('keydown', (e) => this.key(e));
    }
    url(path) { return base(this.kind, this.id, this.code) + (path || ''); }
    gurl(path) { return this.url(`/${encodeURIComponent(this.base)}/${encodeURIComponent(this.view)}${path || ''}`); }

    // ------------------------------------------------------------------ the frame
    build() {
      U.clear(this.dlg);
      const B = (text, title, fn, cls) => el('button', { type: 'button', class: 'btn small' + (cls ? ' ' + cls : ''), text, title, onclick: fn });
      this.stagedChip = el('span', { class: 'chip fr-staged-chip', text: '' });
      this.exportBtn = B('Export', 'one job: the strip packed from every staged and selected frame (the old strip backed up), the look\'s entry written, then an import; nothing else writes the strip', () => this.exportLook(), 'primary');
      this.undoAllBtn = B('Undo all', 'drop every staged choice of this look (the selected frames stay as they are)', () => this.unstageAll());
      const head = el('div', { class: 'sp-modal-head fr-head' },
        el('b', { class: 'fr-title', text: `Frames · ${this.id} · ${this.code}` }),
        el('span', { class: 'muted small', text: `${this.sum.method || ''} · ${this.sum.frame_px} px cells · ${FM.summaryLine(this.sum)}` }),
        this.stagedChip, el('span', { class: 'spacer' }), this.undoAllBtn, this.exportBtn,
        el('button', { type: 'button', class: 'btn small', text: '✕ close', onclick: () => this.dlg.close() }));
      this.tabs = el('div', { class: 'fr-tabs' });
      this.drawTabs();
      // the stage: previous, current (big), next; the guide under
      this.prevImg = el('img', { class: 'fr-side', alt: '' });
      this.nextImg = el('img', { class: 'fr-side', alt: '' });
      this.img = el('img', { class: 'fr-frame', alt: '' });
      this.bigIdx = el('div', { class: 'fr-bigidx', title: 'the slot: the frame\'s index in the animation, 0-based' });
      this.stageBadges = el('div', { class: 'fr-stage-badges' });
      this.prevIdx = el('span', { class: 'fr-side-idx' });
      this.nextIdx = el('span', { class: 'fr-side-idx' });
      const stage = el('div', { class: 'fr-stage-row' },
        el('div', { class: 'fr-side-box', title: 'the previous frame' }, this.prevImg, this.prevIdx),
        el('div', { class: 'fr-stage' }, this.img, this.bigIdx, this.stageBadges),
        el('div', { class: 'fr-side-box', title: 'the next frame' }, this.nextImg, this.nextIdx));
      this.guide = el('div', { class: 'fr-guide' });
      this.fileLine = el('div', { class: 'muted small fr-file' });
      this.playBtn = B('▶ play', 'play / pause (Space)', () => (this.playing ? this.pause() : this.play()));
      this.scrub = el('input', { type: 'range', class: 'fr-scrub', min: 0, max: 0, step: 1, value: 0, title: 'drag through the frames' });
      this.scrub.addEventListener('input', () => { this.pause(); this.showPos(Number(this.scrub.value)); });
      const speed = el('select', { title: 'frames a second (the game\'s own rate for this animation is the default)' });
      for (const f of FM.SPEEDS) speed.appendChild(el('option', { value: f, text: `${f} fps` }));
      speed.addEventListener('change', () => { this.fps = Number(speed.value) || 10; });
      this.speedSel = speed;
      const loopCb = el('input', { type: 'checkbox' });
      loopCb.checked = true;
      loopCb.addEventListener('change', () => { this.loop = loopCb.checked; });
      this.loopCb = loopCb;
      const zoom = el('select', { title: 'the frame\'s size on the stage' });
      for (const z of FM.ZOOMS) zoom.appendChild(el('option', { value: z, text: `${z}x`, selected: z === this.zoom }));
      zoom.addEventListener('change', () => { this.zoom = Number(zoom.value) || 2; this.applyZoom(); });
      const ctl = el('div', { class: 'fr-ctl' },
        B('|◀', 'the first frame (Home)', () => { this.pause(); this.showPos(0); }),
        B('◀', 'one frame back (←)', () => { this.pause(); this.showPos(FM.step(this.pos, this.n(), -1, true)); }),
        this.playBtn,
        B('▶', 'one frame on (→)', () => { this.pause(); this.showPos(FM.step(this.pos, this.n(), 1, true)); }),
        B('▶|', 'the last frame (End)', () => { this.pause(); this.showPos(this.n() - 1); }),
        this.scrub, speed, el('label', { class: 'cb', title: 'off: plays once and stops on the last frame' }, loopCb, el('span', { text: 'loop' })), zoom);
      // the versions of the shown slot
      this.versions = el('div', { class: 'fr-versions' });
      const main = el('div', { class: 'fr-main' }, el('div', { class: 'fr-left' }, stage, this.fileLine, ctl, this.guide), this.versions);
      // the actions on the selection
      this.selLine = el('span', { class: 'fr-selline' });
      this.actions = el('div', { class: 'fr-actions' });
      this.panel = el('div', { class: 'fr-panel', hidden: true });
      // the sheet
      this.sheetHead = el('div', { class: 'fr-sheet-head muted small' });
      this.sheet = el('div', { class: 'fr-sheet' });
      this.stagedList = el('div', { class: 'fr-staged-list' });   // pass 96: the staged changes of this group, in Garry's label form, each with an undo
      this.info = el('div', { class: 'fr-info' });
      this.dlg.append(head, this.tabs, main, this.actions, this.panel, this.sheetHead, this.sheet, this.stagedList, this.info,
        el('details', { class: 'fr-help' }, el('summary', { text: 'How the Frames view works' }), el('p', { class: 'small', text: HELP })));
    }
    drawTabs() {
      U.clear(this.tabs);
      for (const g of this.sum.groups) {
        const b = el('button', { type: 'button', class: 'btn small' + (g.base === this.base && g.view === this.view ? ' on' : ''), title: `${g.key}: ${g.n} frames${g.clip ? ' · clip ' + g.clip : ' · no clip cache (cells only)'}${g.driver ? ' · driver ' + g.driver : ''}`,
          onclick: () => this.show(g.base, g.view) },
          el('span', { text: `${FM.groupLabel(g)} · ${g.n}` }), g.staged ? el('span', { class: 'fr-tab-staged', text: String(g.staged), title: `${g.staged} staged` }) : null, g.pinned ? el('span', { class: 'fr-tab-pinned', text: '📌', title: `${g.pinned} pinned` }) : null);
        b.dataset.key = g.key;
        this.tabs.appendChild(b);
      }
      const total = this.sum.groups.reduce((a, g) => a + (Number(g.staged) || 0), 0);
      this.stagedChip.textContent = total ? `${total} staged` : 'nothing staged';
      this.stagedChip.classList.toggle('on', total > 0);
      this.exportBtn.disabled = !total || this.busy;
      this.exportBtn.textContent = total ? `Export (${total})` : 'Export';
      this.undoAllBtn.disabled = !total || this.busy;
    }
    n() { return this.detail ? this.detail.slots.length : 0; }
    slotRec(k) { return this.detail && this.detail.slots[k] ? this.detail.slots[k] : null; }

    // ------------------------------------------------------------------ data
    async refreshSummary() {
      const s = await summary(this.kind, this.id, this.code);
      if (s && s.ok) { this.sum = s; this.drawTabs(); }
    }
    async fetchDetail() {
      const d = await fetchJson(this.gurl(''), null);
      if (d && d.ok) this.detail = d;
      return d;
    }
    async show(b, v, slot) {
      const g = this.sum.groups.find((x) => x.base === b && x.view === v) || this.sum.groups.find((x) => x.base === 'run' && x.view === 'side') || this.sum.groups.find((x) => x.base === 'run') || this.sum.groups[0];
      this.base = g.base; this.view = g.view;
      this.pause();
      this.sel = new Set(); this.anchor = null; this.others = null;
      this.panel.hidden = true; U.clear(this.panel);
      this.drawTabs();
      this.sheetHead.textContent = 'loading…';
      const d = await this.fetchDetail();
      if (!this.dlg.isConnected) return;
      if (!d || !d.ok) { this.sheetHead.textContent = `could not load ${g.key}: ${(d && d.error) || 'no answer'}`; return; }
      this.fps = FM.previewFps(this.kind, this.base, this.detail.fps);
      for (const op of this.speedSel.options) op.selected = Number(op.value) === this.fps;
      if (!Array.from(this.speedSel.options).some((op) => op.selected)) this.speedSel.appendChild(el('option', { value: this.fps, text: `${this.fps} fps`, selected: true }));
      this.loop = !!this.detail.loop; this.loopCb.checked = this.loop;
      this.applyZoom();
      this.redrawAll();
      this.showPos(slot != null ? Math.max(0, Math.min(this.n() - 1, Number(slot))) : 0);
      if (this.detail.loop) this.play();
      this.watchJobs();
    }
    /** The group fetched again (a landing, a choice): the current slot and selection kept. */
    async reload() {
      const d = await this.fetchDetail();
      if (!d || !d.ok || !this.dlg.isConnected) return;
      this.redrawAll();
      this.showPos(this.pos);
      await this.refreshSummary();
    }
    redrawAll() {
      this.preload = FM.playlist(this.detail).map((f) => { const im = new Image(); im.src = f.url; return im; });
      this.drawSheet();
      this.drawStaged();
      this.drawVersions();
      this.drawActions();
      this.drawInfo();
    }
    /** pass 96: the staged changes of the shown group as lines (`Run / Side / Frame 07 <- SP-A / Run / Side / Frame 07 / v2 (VACE)`), each with an undo. */
    drawStaged() {
      U.clear(this.stagedList);
      const d = this.detail;
      const rows = (d.slots || []).filter((s) => s.staged);
      if (!rows.length) return;
      this.stagedList.appendChild(el('div', { class: 'muted small', text: `${rows.length} staged change${rows.length === 1 ? '' : 's'} in ${FM.groupLabel(d)} (Export packs them; ✕ undoes one):` }));
      for (const s of rows) {
        const v = (s.versions || []).find((x) => x.id === s.staged) || {};
        const here = String(s.name || FM.frameLabel(d.code, d.base, d.view, s.slot)).split(' / ').slice(1).join(' / ');
        this.stagedList.appendChild(el('div', { class: 'row' },
          el('button', { type: 'button', class: 'btn small ghost', text: '✕', title: 'unstage this frame (Undo)', onclick: () => this.unstage(s.slot) }),
          el('span', { text: `${here} <- ${FM.nameOf(v, d)} (${(FM.SOURCE_TEXT[v.source] || v.source || '?')})`, title: FM.versionText(v) })));
      }
    }
    applyZoom() {
      const px = CELL * this.zoom;
      this.img.style.width = this.img.style.height = `${px}px`;
      const side = Math.round(px * 0.55);
      this.prevImg.style.width = this.prevImg.style.height = `${side}px`;
      this.nextImg.style.width = this.nextImg.style.height = `${side}px`;
    }

    // ------------------------------------------------------------------ the stage
    showPos(k) {
      const n = this.n();
      this.scrub.max = String(Math.max(0, n - 1));
      if (!n) { this.img.removeAttribute('src'); this.bigIdx.textContent = '–'; return; }
      this.pos = Math.max(0, Math.min(n - 1, Number(k) || 0));
      this.slot = this.pos;
      const s = this.slotRec(this.pos);
      this.img.src = s.url || '';
      this.bigIdx.textContent = String(this.pos);
      this.scrub.value = String(this.pos);
      const p = this.slotRec(FM.step(this.pos, n, -1, true)), q = this.slotRec(FM.step(this.pos, n, 1, true));
      this.prevImg.src = p ? p.url || '' : ''; this.nextImg.src = q ? q.url || '' : '';
      this.prevIdx.textContent = p ? String(p.slot) : ''; this.nextIdx.textContent = q ? String(q.slot) : '';
      const eff = (s.versions || []).find((v) => v.id === s.effective);
      this.fileLine.textContent = `slot ${this.pos} of ${n} · ${eff ? FM.versionText(eff) : 'no version'}${s.effective_how === 'staged' ? ' · STAGED' : ''}`;
      U.clear(this.stageBadges);
      for (const b of FM.badges(s, this.detail.flags ? this.detail.flags[String(this.pos)] : null)) this.stageBadges.appendChild(el('span', { class: 'fr-badge ' + b.cls, text: b.text, title: b.title }));
      U.clear(this.guide);
      if (s.driver_url) {
        const gi = el('img', { src: s.driver_url, alt: '', title: `the driver's frame ${s.driver_frame} (${this.detail.driver.name}): what the clip followed here, the guide a repair follows` });
        gi.addEventListener('click', () => StripPlayer.openImage(s.driver_url, `${this.detail.driver.name} · ${this.view} · frame ${s.driver_frame}`));
        this.guide.append(el('span', { class: 'muted small', text: `guide: ${this.detail.driver.name} frame ${s.driver_frame}` }), gi);
      } else this.guide.appendChild(el('span', { class: 'muted small', text: this.detail.driver ? '' : 'no driver for this animation: a repair fills the frame freely from its neighbours' }));
      if (this.cells) for (const [i, c] of this.cells) c.classList.toggle('cur', i === this.pos);
      if (!this.playing) this.drawVersions();
    }
    play() {
      this.playing = true;
      this.playBtn.textContent = '❚❚ pause';
      if (!this.loop && this.pos >= this.n() - 1) this.showPos(0);
      if (!this.raf) { this.last = performance.now(); this.acc = 0; this.raf = requestAnimationFrame((t) => this.tick(t)); }
    }
    pause() { const was = this.playing; this.playing = false; this.playBtn.textContent = '▶ play'; if (this.raf) cancelAnimationFrame(this.raf); this.raf = 0; if (was) this.drawVersions(); }
    stop() { this.pause(); this.preload = []; if (this.pollTimer) clearTimeout(this.pollTimer); this.pollTimer = 0; }
    tick(t) {
      this.raf = 0;
      if (!this.playing || !this.dlg.isConnected) return;
      this.acc += Math.min(0.25, (t - this.last) / 1000);
      this.last = t;
      const per = 1 / this.fps;
      const n = this.n();
      while (this.acc >= per && n > 1) {
        this.acc -= per;
        if (!this.loop && this.pos >= n - 1) { this.showPos(n - 1); this.pause(); return; }
        this.showPos(FM.step(this.pos, n, 1, true));
      }
      this.raf = requestAnimationFrame((t2) => this.tick(t2));
    }
    key(e) {
      const t = e.target;
      const tag = t && t.tagName;
      if ((tag === 'INPUT' && !['range', 'checkbox'].includes(t.type)) || tag === 'TEXTAREA' || tag === 'SELECT') return;
      const n = this.n();
      if (e.key === ' ') { e.preventDefault(); this.playing ? this.pause() : this.play(); }
      else if (e.key === 'ArrowRight') { e.preventDefault(); this.pause(); this.showPos(FM.step(this.pos, n, 1, true)); }
      else if (e.key === 'ArrowLeft') { e.preventDefault(); this.pause(); this.showPos(FM.step(this.pos, n, -1, true)); }
      else if (e.key === 'Home') { e.preventDefault(); this.pause(); this.showPos(0); }
      else if (e.key === 'End') { e.preventDefault(); this.pause(); this.showPos(n - 1); }
      else return;
      e.stopPropagation();
    }

    // ------------------------------------------------------------------ the sheet
    drawSheet() {
      U.clear(this.sheet);
      const n = this.n();
      const flags = this.detail.flags || {};
      const nFlag = Object.values(flags).filter((f) => f && Object.keys(f).length).length;
      this.sheetHead.textContent = `all ${n} frames of ${FM.groupLabel(this.detail)} (${this.detail.key}), numbered by slot: click one to show it, shift-click a range, ctrl-click to add; ${nFlag ? nFlag + ' flagged (hints, not verdicts)' : 'nothing flagged (the flags miss ghost legs: look)'}`
        + (this.detail.clip ? '' : ' · no clip cache: this animation holds strip cells only, repairs run in cell space (softer frames)');
      this.cells = new Map();
      for (const s of this.detail.slots) {
        const bs = FM.badges(s, flags[String(s.slot)]);
        const c = el('button', { type: 'button', class: 'fr-cell' + (s.staged ? ' staged' : '') + (s.pinned ? ' pinned' : '') + (this.sel.has(s.slot) ? ' sel' : ''), title: `${s.name || 'slot ' + s.slot}${bs.length ? ': ' + bs.map((b) => b.text).join(', ') : ''}` },
          el('img', { src: s.url || '', alt: '', loading: 'lazy' }), el('span', { class: 'fr-cell-idx', text: String(s.slot) }),
          bs.length ? el('span', { class: 'fr-cell-badges' }, bs.map((b) => el('span', { class: 'fr-mini ' + b.cls, text: b.key === 'staged' ? '✓' : b.key === 'pinned' ? '📌' : b.key === 'differs' ? '≠' : '⚠', title: b.title }))) : null);
        c.addEventListener('click', (e) => {
          const r = FM.select(this.sel, s.slot, { shift: e.shiftKey, ctrl: e.ctrlKey || e.metaKey }, this.anchor);
          this.sel = r.set; this.anchor = r.anchor;
          for (const [i, x] of this.cells) x.classList.toggle('sel', this.sel.has(i));
          this.pause();
          this.showPos(s.slot);
          this.drawActions();
        });
        this.cells.set(s.slot, c);
        this.sheet.appendChild(c);
      }
    }

    // ------------------------------------------------------------------ the versions drawer
    drawVersions() {
      U.clear(this.versions);
      const s = this.slotRec(this.slot);
      if (!s) return;
      const head = el('div', { class: 'fr-vhead' }, el('b', { text: `Versions of slot ${s.slot}` }), el('span', { class: 'muted small', text: `${s.versions.length}: click one to stage it` }));
      this.versions.appendChild(head);
      const list = el('div', { class: 'fr-vlist' });
      for (const v of FM.versionsNewestFirst(s.versions)) {
        const isSel = v.id === s.selected, isSt = v.id === s.staged, isEff = v.id === s.effective;
        const tile = el('div', { class: 'fr-vtile' + (isEff ? ' eff' : '') + (isSel ? ' selected' : '') + (isSt ? ' staged' : ''), title: FM.versionText(v) + (v.prompt ? '\n' + v.prompt : '') });
        const img = el('img', { src: v.url, alt: '', loading: 'lazy' });
        img.addEventListener('click', () => this.stage(s.slot, v.id));
        tile.appendChild(img);
        // pass 96: Garry's label (`SP-B / Run / Side / Frame 07 / v2`); the short `label` stays in the hover text for scripts
        tile.appendChild(el('div', { class: 'fr-vlabel' }, el('b', { class: 'fr-vname', text: FM.nameOf(v, this.detail), title: v.label || '' }),
          el('span', { class: 'muted small' }, el('span', { text: (FM.SOURCE_TEXT[v.source] || v.source || '') + (v.from && (v.from.name || v.from.label) ? ` (${v.from.name || v.from.label}${!v.from.name && v.from.code ? ' of ' + v.from.code : ''}${v.from.removed ? ', removed look' : ''})` : '') }),
            FM.sourceMark(v) ? el('span', { class: 'fr-mark ' + (v.source === 'old_roll' ? 'old' : 'archived'), text: FM.sourceMark(v) }) : null)));
        const marks = el('div', { class: 'fr-vmarks' });
        if (isSt) marks.appendChild(el('span', { class: 'fr-badge staged', text: 'staged' }));
        if (isSel) marks.appendChild(el('span', { class: 'fr-badge ' + (s.pinned ? 'pinned' : 'sel'), text: s.pinned ? 'pinned' : 'selected', title: s.pinned ? 'a human chose it: a re-roll keeps it' : 'what the installed strip shows (or the last export packed)' }));
        if (v.qa && v.qa.vision && v.qa.vision.answer) marks.appendChild(el('span', { class: 'fr-badge vision', text: 'vision: ' + (v.qa.vision.answer.note || JSON.stringify(v.qa.vision.answer)).slice(0, 60), title: JSON.stringify(v.qa.vision.answer) + '\n' + (v.qa.vision.note || '') }));
        tile.appendChild(marks);
        const acts = el('div', { class: 'fr-vacts' });
        if (!isEff) acts.appendChild(el('button', { type: 'button', class: 'btn small', text: 'Stage', title: 'the preview plays this one; Export packs it', onclick: () => this.stage(s.slot, v.id) }));
        if (isSel && !s.pinned) acts.appendChild(el('button', { type: 'button', class: 'btn small ghost', text: 'Pin', title: 'keep this choice through re-rolls', onclick: () => this.pin(s.slot, v.id, true) }));
        if (isSel && s.pinned) acts.appendChild(el('button', { type: 'button', class: 'btn small ghost', text: 'Unpin', onclick: () => this.pin(s.slot, v.id, false) }));
        if (isSt) acts.appendChild(el('button', { type: 'button', class: 'btn small ghost', text: 'Unstage', title: 'back to the selected version (Undo)', onclick: () => this.unstage(s.slot) }));
        acts.appendChild(el('button', { type: 'button', class: 'btn small ghost', text: 'large', onclick: () => StripPlayer.openImage(v.url, `${this.id} · ${FM.nameOf(v, this.detail)}`) }));
        // pass 96 (Garry's decision 10): no Delete button: a frame version is never deleted (the route refuses too)
        tile.appendChild(acts);
        list.appendChild(tile);
      }
      this.versions.appendChild(list);
    }

    // ------------------------------------------------------------------ the actions
    drawActions() {
      U.clear(this.actions);
      const sel = Array.from(this.sel).sort((a, b) => a - b);
      const n = this.n();
      const B = (text, title, fn, cls, disabled) => el('button', { type: 'button', class: 'btn small' + (cls ? ' ' + cls : ''), text, title, disabled: !!disabled || this.busy, onclick: fn });
      this.selLine.textContent = sel.length ? `selected: ${FM.slotsText(sel)} (${sel.length})` : 'no frames selected (click a frame on the sheet; shift-click a range)';
      const plan = FM.repairPlan(n, !!this.detail.loop, sel, 'auto');
      const rep = this.detail.repairable || { ok: true, why: '', rule: {} };
      const ruleWord = rep.rule && rep.rule.vace ? ` · rule for ${this.detail.method || 'this method'}: VACE ${rep.rule.vace}` : '';
      this.actions.append(this.selLine,
        B(rep.ok ? 'Repair with VACE…' : 'Repair with VACE… (refused by the rule)', plan.ok ? (rep.ok ? `paint ${sel.length} frame${sel.length === 1 ? '' : 's'} anew with Wan 2.2 Fun VACE, the others kept: ${plan.note}${ruleWord}` : `${rep.why}${ruleWord}; the form offers "fill freely anyway"`) : plan.note, () => this.repairForm(sel), rep.ok ? 'primary' : '', !plan.ok),
        B('From another look…', 'the same slot in every other look of this asset (removed looks too, marked): pick a frame of theirs (a copy becomes a version here, staged)', () => this.othersPanel(sel), '', !sel.length && n === 0),
        B('Fill from neighbours…', plan.ok ? `a VACE repair with no guide: the ${sel.length} chosen frame${sel.length === 1 ? '' : 's'} painted from the neighbours alone (no RIFE / FILM model is installed on the server; this is the same job with guide = free)${rep.ok ? '' : '; ' + rep.why}` : plan.note, () => this.repairForm(sel, 'free'), '', !plan.ok),
        B('Ask the local vision model', 'LM Studio looks at the shown frame and says what seems wrong (honestly: it cannot count limbs reliably)', () => this.ask(), '', false),
        B('Unstage selected', 'drop the staged choices of the selected frames (Undo)', () => this.unstageSel(sel), '', !sel.some((k) => this.slotRec(k) && this.slotRec(k).staged)));
    }
    async act(fn, busyText) {
      if (this.busy) return null;
      this.busy = true;
      this.drawActions(); this.drawTabs();
      if (busyText) status(`${this.id} ${this.code}: ${busyText}`, 'busy');
      let res = null;
      try { res = await fn(); } finally { this.busy = false; }
      if (!this.dlg.isConnected) return res;
      if (res && res.group && res.group.ok) { this.detail = res.group; this.redrawAll(); this.showPos(this.pos); await this.refreshSummary(); }
      else if (res && res.ok) await this.reload();
      else { this.drawActions(); this.drawTabs(); }
      if (res && !res.ok) status(`${this.id} ${this.code}: ${res.error || 'refused'}`, 'bad');
      return res;
    }
    stage(slot, vid) { return this.act(() => post(this.gurl('/stage'), { slot, version: vid }), `slot ${slot} staged`); }
    unstage(slot) { return this.act(() => post(this.gurl('/unstage'), { slot }), `slot ${slot} unstaged`); }
    pin(slot, vid, pinned) { return this.act(() => post(this.gurl('/pin'), { slot, version: vid, pinned }), pinned ? `slot ${slot} pinned` : `slot ${slot} unpinned`); }
    async unstageSel(sel) {
      for (const k of sel) if (this.slotRec(k) && this.slotRec(k).staged) await post(this.gurl('/unstage'), { slot: k });
      await this.reload();
    }
    async unstageAll() {
      if (!confirm(`Drop every staged choice of ${this.code} (${this.sum.groups.reduce((a, g) => a + (g.staged || 0), 0)} frames)? The selected frames stay as they are.`)) return;
      for (const g of this.sum.groups) if (g.staged) await post(this.url(`/${g.base}/${g.view}/unstage`), {});
      await this.reload();
    }
    async ask() {
      const s = this.slotRec(this.slot);
      if (!s) return;
      const res = await this.act(() => post(this.gurl('/ask'), { slot: s.slot, version: s.effective }), 'asking the local vision model…');
      if (res && res.ok) status(`${this.id} ${this.code} slot ${s.slot}: the vision model says ${JSON.stringify(res.vision.answer)} (a hint: it cannot count limbs reliably)`, 'good');
    }
    async exportLook() {
      const total = this.sum.groups.reduce((a, g) => a + (g.staged || 0), 0);
      if (!total) return;
      // pass 96 (Garry's decision 5): EVERY export that replaces an installed strip shows one box listing the whole batch
      // (before / after per frame, the flag deltas, whether the game plays the look, the backup); one click sends confirm: true
      const b = await fetchJson(this.url('/batch'), null);
      if (!this.dlg.isConnected) return;
      let yes;
      if (b && b.ok && Array.isArray(b.items) && b.items.length) yes = await this.batchPanel(b);
      else yes = confirm(FM.exportConfirmText(this.code, total, true, this.id));   // an older server without the batch route: the plain line
      if (!yes) return;
      let res = await this.act(() => post(this.url('/export'), { confirm: true }), 'export queued…');
      if (res && !res.ok && res.needs_confirm) {
        // the route still refuses without confirm; it should not reach here, but say so plainly and offer the box again
        if (res.batch && res.batch.items && res.batch.items.length ? !(await this.batchPanel(res.batch)) : !confirm(res.error || FM.exportConfirmText(this.code, total, true, this.id))) return;
        res = await this.act(() => post(this.url('/export'), { confirm: true }), 'export queued…');
      }
      if (res && res.ok) status(`${this.id} ${this.code}: export job #${String((res.job && res.job.id) || '').slice(-4)} queued: the strip is packed from ${total} changed frame${total === 1 ? '' : 's'}, the look's entry written, then an import (see the Jobs tab; it waits for a running repair of this look)`, 'good');
      this.watchJobs(true);
    }
    /** The batch box inside the view (this.panel): resolves true on "Export all", false on cancel. */
    batchPanel(b) {
      return new Promise((resolve) => {
        U.clear(this.panel);
        this.panel.hidden = false;
        const done = (v) => { this.panel.hidden = true; U.clear(this.panel); resolve(v); };
        this.panel.appendChild(el('div', { class: 'fr-panel-head' }, el('b', { text: `Export ${this.code}: confirm the batch` }), el('span', { class: 'spacer' }), el('button', { type: 'button', class: 'btn small ghost', text: '✕', onclick: () => done(false) })));
        this.panel.appendChild(batchContent(b));
        this.panel.appendChild(el('div', { class: 'row' },
          el('button', { type: 'button', class: 'btn small primary', text: `Export all ${b.items.length} (one click for the whole batch)`, onclick: () => done(true) }),
          el('button', { type: 'button', class: 'btn small ghost', text: 'Cancel', onclick: () => done(false) })));
        this.panel.scrollIntoView({ block: 'nearest' });
      });
    }

    // ------------------------------------------------------------------ the repair form
    repairForm(sel, guideDefault) {
      U.clear(this.panel);
      this.panel.hidden = false;
      const n = this.n();
      const plan = FM.repairPlan(n, !!this.detail.loop, sel, 'auto');
      const clip = this.detail.clip || {};
      const guide = el('select', { title: 'what the redone frames follow: the driver\'s frames fitted onto the kept figure (the pose the clip was walked on), or nothing (filled from the neighbours alone; the only choice without a driver)' },
        el('option', { value: 'driver', text: this.detail.driver ? `the driver (${this.detail.driver.name})` : 'the driver (none: free)', selected: guideDefault !== 'free' && !!this.detail.driver }),
        el('option', { value: 'free', text: 'free: from the neighbours alone', selected: guideDefault === 'free' || !this.detail.driver }));
      const ta = el('textarea', { class: 'txt fr-prompt', spellcheck: false, placeholder: 'the words the frames are painted with (empty: the clip\'s own)' });
      ta.value = clip.prompt || '';
      const seed = el('input', { type: 'number', class: 'num', value: 0, min: 0, step: 1, title: '0 = the clip\'s seed moved by the slots; another number for another roll' });
      const win = el('select', { title: 'how much of the animation goes in' }, el('option', { value: 'auto', text: `auto (${((this.detail.repairable || {}).rule || {}).profile && ((this.detail.repairable || {}).rule || {}).profile.window ? ((this.detail.repairable || {}).rule || {}).profile.window + ', the method's profile' : plan.mode})`, selected: true }), el('option', { value: 'double', text: 'double: the loop twice' }), el('option', { value: 'single', text: 'single: the loop once' }));
      const note = el('div', { class: 'muted small', text: `${plan.note}${this.detail.driver ? ` · guide: ${this.detail.driver.name}'s frames fitted onto the kept figure` : ' · no driver: the frames are filled from their neighbours'}${this.detail.ref_still ? ' · reference: ' + this.detail.ref_still.split('/').pop() : ' · reference: the fullest kept frame (no painting in the cache)'}${clip.key ? '' : ' · NO CLIP CACHE: the kept frames are strip cells put back on a canvas (softer result)'}` });
      const msg = el('span', { class: 'muted small' });
      // pass 95 resume (AN-01): the method's repair rule; a procedural animation needs "fill freely anyway" on purpose
      const rep = this.detail.repairable || { ok: true, why: '', rule: {} };
      const freeCb = el('input', { type: 'checkbox' });
      const ruleRow = rep.ok ? null : el('div', { class: 'row' }, el('span', { class: 'warn-text small', text: rep.why }),
        el('label', { class: 'cb', title: 'send the job anyway: a free fill from the neighbours (no guide); the method\'s rule says the still is the thing to fix' }, freeCb, el('span', { text: 'fill freely anyway' })));
      const queue = el('button', { type: 'button', class: 'btn small primary', text: `Queue the repair of ${FM.slotsText(sel)}`, onclick: async () => {
        if (!rep.ok && !freeCb.checked) { msg.textContent = 'refused by the rule: tick "fill freely anyway" to send it as a free fill'; return; }
        queue.disabled = true;
        const res = await post(this.gurl('/repair'), { slots: sel, prompt: ta.value.trim(), seed: Number(seed.value) || 0, window: win.value, guide: guide.value, free_fill: !rep.ok && freeCb.checked });
        if (!res.ok) { msg.textContent = `refused: ${res.error || 'no answer'}`; queue.disabled = false; return; }
        msg.textContent = `queued #${String((res.job && res.job.id) || '').slice(-4)}: the new frames land here as versions (staged) when it is done; the Jobs tab shows its progress`;
        status(`${this.id} ${this.code}: VACE repair of ${this.detail.key} slots ${FM.slotsText(sel)} queued`, 'good');
        if (typeof Jobs !== 'undefined' && typeof Jobs.poll === 'function') { try { await Jobs.poll(); } catch (_) { /* the list as it was */ } }
        this.watchJobs(true);
      } });
      this.panel.append(el('div', { class: 'fr-panel-head' }, el('b', { text: `Repair with VACE: slots ${FM.slotsText(sel)} of ${this.detail.key}` }), el('span', { class: 'spacer' }), el('button', { type: 'button', class: 'btn small ghost', text: '✕', onclick: () => { this.panel.hidden = true; U.clear(this.panel); } })),
        el('div', { class: 'row' }, el('span', { class: 'muted small', text: 'words' })), ta,
        el('div', { class: 'row' }, el('label', { class: 'cb' }, el('span', { text: 'seed' }), seed), el('label', { class: 'cb' }, el('span', { text: 'window' }), win), el('label', { class: 'cb' }, el('span', { text: 'guide' }), guide)),
        note, ruleRow, el('div', { class: 'row' }, queue, msg));
    }

    // ------------------------------------------------------------------ from another look
    /** pass 96 (AN-07, Garry's decision 2): the picker with filters by look, animation, view, time and source (newest first;
     *  lazy: one group's versions fetched at a time), the marks removed / old roll / archived where the store has them;
     *  a different animation or view only on purpose (an amber warning: the poses differ). */
    async othersPanel(sel) {
      const f = this.pickFilters || (this.pickFilters = { look: '', base: this.base, view: this.view, days: 0, source: '', raw: false });
      if (!this.sum.groups.some((g) => g.base === f.base && g.view === f.view)) { f.base = this.base; f.view = this.view; }
      U.clear(this.panel);
      this.panel.hidden = false;
      const close = () => { this.panel.hidden = true; U.clear(this.panel); };
      this.panel.appendChild(el('div', { class: 'fr-panel-head' }, el('b', { text: `From another look: ${this.detail.key}` }), el('span', { class: 'muted small', text: 'loading…' }), el('span', { class: 'spacer' }), el('button', { type: 'button', class: 'btn small ghost', text: '✕', onclick: close })));
      const otherGroup = f.base !== this.base || f.view !== this.view;
      const r = await fetchJson(this.url(`/${encodeURIComponent(f.base)}/${encodeURIComponent(f.view)}/others`), null);
      if (!this.dlg.isConnected) return;
      U.clear(this.panel);
      const slots = sel.length ? sel : [this.slot];
      this.panel.appendChild(el('div', { class: 'fr-panel-head' }, el('b', { text: `From another look: ${this.detail.key}, slot${slots.length > 1 ? 's' : ''} ${FM.slotsText(slots)}` }), el('span', { class: 'muted small', text: 'a frame of theirs copied here becomes a version of this slot (staged); the other look is not touched; every frame ever generated for this asset that the store holds is listed, newest first' }), el('span', { class: 'spacer' }), el('button', { type: 'button', class: 'btn small ghost', text: '✕', onclick: close })));
      const looks = r && r.ok ? r.looks : [];
      // the filter row
      const sel1 = (opts, cur, onchange, title) => { const s = el('select', { title }); for (const o of opts) s.appendChild(el('option', { value: o.v, text: o.label, selected: String(o.v) === String(cur) })); s.addEventListener('change', () => { onchange(s.value); this.othersPanel(sel); }); return s; };
      const lookOpts = [{ v: '', label: 'every look' }].concat(looks.map((o) => ({ v: o.code, label: o.code + (o.removed ? ' (removed)' : '') })));
      const groupOpts = this.sum.groups.map((g) => ({ v: `${g.base}/${g.view}`, label: FM.groupLabel(g) + (g.base === this.base && g.view === this.view ? ' (this one)' : '') }));
      this.panel.appendChild(el('div', { class: 'fr-filters' },
        el('span', { class: 'muted', text: 'look' }), sel1(lookOpts, f.look, (v) => { f.look = v; }, 'only this look'),
        el('span', { class: 'muted', text: 'animation · view' }), sel1(groupOpts, `${f.base}/${f.view}`, (v) => { const [b2, v2] = v.split('/'); f.base = b2; f.view = v2; }, 'the other looks\' frames of this animation and view (one group fetched at a time)'),
        el('span', { class: 'muted', text: 'time' }), sel1(FM.TIME_OPTIONS, f.days, (v) => { f.days = Number(v) || 0; }, 'only versions made since then'),
        el('span', { class: 'muted', text: 'source' }), sel1(FM.SOURCE_OPTIONS, f.source, (v) => { f.source = v; }, 'installed, re-rolled, VACE, copied, old roll, archived'),
        (() => { const cb = el('input', { type: 'checkbox', checked: f.raw }); cb.addEventListener('change', () => { f.raw = cb.checked; this.othersPanel(sel); }); return el('label', { class: 'cb', title: 'only versions with a clip frame (the fit sizes a copy exactly)' }, cb, el('span', { text: 'only raw' })); })(),
        otherGroup ? el('span', { class: 'warn-text', text: `${f.base} · ${f.view} is not ${this.detail.key}: the poses will not match this animation; copy only on purpose` }) : null));
      if (!looks.length) { this.panel.appendChild(el('p', { class: 'muted small', text: `no other look of ${this.id} has a ${f.base} ${f.view} animation with a strip` })); return; }
      const drv = this.detail.driver ? this.detail.driver.name : '';
      let shown = 0;
      for (const o of looks) {
        if (f.look && o.code !== f.look) continue;
        const warns = FM.compat(o, this.n(), this.detail.frame_px, drv);
        const box = el('div', { class: 'fr-other' + (o.removed ? ' removed' : '') });
        box.appendChild(el('div', { class: 'fr-other-head' }, el('b', { text: o.code }),
          o.removed ? el('span', { class: 'chip', text: 'removed look', title: 'the JSON no longer lists this look; its frames stay in the store and can be copied (a copy never links back)' }) : null,
          el('span', { class: 'muted small', text: o.note || '' }), warns.length ? el('span', { class: 'warn-text small', text: warns.join('; ') }) : el('span', { class: 'muted small', text: 'compatible' })));
        for (const k of slots) {
          const os = o.slots.find((x) => x.slot === k);
          const row = el('div', { class: 'fr-other-row' }, el('span', { class: 'fr-other-slot', text: `${String(this.slotRec(k) && this.slotRec(k).name || 'slot ' + k).split(' / ').slice(1).join(' / ') || 'slot ' + k} ←` }));
          if (!os) { row.appendChild(el('span', { class: 'muted small', text: `${o.code} has no slot ${k}` })); box.appendChild(row); continue; }
          const list = FM.filterVersions(os.versions, f);
          if (!list.length) { row.appendChild(el('span', { class: 'muted small', text: 'nothing matches the filters' })); box.appendChild(row); continue; }
          for (const v of list) {
            shown++;
            const tile = el('button', { type: 'button', class: 'fr-pick' + (v.id === os.effective ? ' eff' : ''), title: `${FM.versionText(v)}${v.id === os.effective ? ' (what ' + o.code + ' plays)' : ''}: copy it into slot ${k} of ${this.code}` },
              el('img', { src: v.url, alt: '', loading: 'lazy' }), el('span', { class: 'small', text: (v.name || v.label) + (v.raw ? '' : ' (cell)') }),
              FM.sourceMark(v) ? el('span', { class: 'fr-mark ' + (v.source === 'old_roll' ? 'old' : 'archived'), text: FM.sourceMark(v) }) : null);
            tile.addEventListener('click', async () => {
              tile.disabled = true;
              const from = { code: o.code, slot: k, version: v.id };
              if (otherGroup) { from.base = f.base; from.view = f.view; }
              const res = await this.act(() => post(this.gurl('/copy'), { slot: k, from }), `copying ${v.name || v.label} into slot ${k}…`);
              if (res && res.ok) status(`${this.code} slot ${k}: ${v.name || v.label} copied in as ${res.version.name || res.version.label}, staged`, 'good');
              tile.disabled = false;
            });
            row.appendChild(tile);
          }
          box.appendChild(row);
        }
        this.panel.appendChild(box);
      }
      if (!shown) this.panel.appendChild(el('p', { class: 'muted small', text: 'nothing matches the filters (old rolls and archived strips are not imported into the store yet: a later pass)' }));
    }

    // ------------------------------------------------------------------ info, and the watch on running repairs
    drawInfo() {
      U.clear(this.info);
      const d = this.detail;
      const fit = d.fit || {};
      this.info.append(
        el('div', {}, el('b', { text: 'Made by: ' }), el('span', { text: `${d.method || '?'} · ${d.clip ? 'clip ' + d.clip.key + ' (' + d.clip.kind + ', ' + d.clip.full + ' frames painted, ' + d.clip.out + ' kept)' : 'no clip cache for this animation (procedural, or painted before the cache was kept)'}${d.driver ? ' · driver ' + d.driver.name + ' (' + d.driver.kind + ')' : ' · no driver'}` })),
        el('div', {}, el('b', { text: 'Fit: ' }), el('span', { text: fit.source === 'measured' ? `measured from ${fit.pairs} installed frames and their clip frames (scale ${Number(fit.s).toFixed(3)}, residual ${Number(fit.residual_px).toFixed(1)} px): a repaired frame is placed exactly as the pipeline placed the clip's` : 'default (no clip frames to measure from): a repaired frame is placed by the cell\'s size' })),
        el('div', {}, el('b', { text: 'Store: ' }), el('code', { text: d.path || '' }), el('span', { class: 'muted small', text: ` · every version is a PNG + JSON there (store layout ${d.store_version || '?'}); no version is ever deleted (pass 96)` })),
        d.lost_pins && d.lost_pins.length ? el('div', { class: 'warn-text small' }, el('b', { text: 'Pins a landing could not re-apply: ' }), el('span', { text: d.lost_pins.map((p) => `slot ${p.slot} (${p.why})`).join('; ') + '; their versions are kept' })) : null,
        el('div', { class: 'muted small fr-where' }, el('b', { text: 'Where frames live: ' }), el('span', { text: FM.whereLine(d) })),
        d.repairable && !d.repairable.ok ? el('div', { class: 'warn-text small' }, el('b', { text: 'Repair rule: ' }), el('span', { text: d.repairable.why })) : null);
    }
    /** While a repair or export job of this look is queued or running (or for half an hour after this view queued
     *  one, when the Jobs tab is not polling), the group is fetched again every 5 s, so new versions appear. */
    watchJobs(queued) {
      if (this.pollTimer) clearTimeout(this.pollTimer);
      if (queued) this.expectUntil = Date.now() + 30 * 60 * 1000;
      const live = () => (typeof Jobs !== 'undefined' && typeof Jobs.jobsFor === 'function')
        ? Jobs.jobsFor(this.kind, this.id, this.code).some((j) => ['queued', 'running'].includes(j.state) && ['frames_repair', 'frames_export', 'look'].includes(j.kind)) : false;
      const tickFn = async () => {
        this.pollTimer = 0;
        if (!this.dlg.isConnected) return;
        if (typeof Jobs !== 'undefined' && typeof Jobs.poll === 'function') { try { await Jobs.poll(); } catch (_) { /* the list as it was */ } }
        const on = live();
        if (on || Date.now() < (this.expectUntil || 0)) {
          await this.reload();
          this.pollTimer = setTimeout(tickFn, 5000);
        }
      };
      if (live() || Date.now() < (this.expectUntil || 0)) this.pollTimer = setTimeout(tickFn, 5000);
    }
  }

  /** pass 96: the batch as the one confirm box shows it: the summary line, then every change as a before / after pair with
   *  its line and the flag deltas. Shared by the view's panel and the standalone box (the request card's Approve). */
  function batchContent(b) {
    const box = el('div', { class: 'fr-batch' });
    box.appendChild(el('div', { class: 'fr-batch-sum' + (b.in_play ? ' inplay' : ''), text: FM.batchSummary(b) }));
    for (const ln of FM.batchLines(b)) {
      const pic = (side) => side && side.url ? el('img', { src: side.url, alt: '', title: side.name || side.label || '' }) : el('span', { class: 'fr-batch-none', text: side ? '?' : 'none' });
      box.appendChild(el('div', { class: 'fr-batch-row' + (ln.why === 'pinned' ? ' pinned' : '') },
        pic(ln.from), el('span', { class: 'fr-batch-arrow', text: '→' }), pic(ln.to),
        el('div', { class: 'fr-batch-text' }, el('code', { text: ln.line }),
          el('span', { class: 'delta' + (/raises/.test(ln.deltas) ? ' raised' : ''), text: ln.deltas }),
          ln.from && ln.from.name ? el('span', { class: 'muted small', text: `was ${ln.from.name}` }) : null)));
    }
    return box;
  }

  /** pass 96: the one confirm box as a standalone dialog over GET /api/frames/<kind>/<id>/<code>/batch, for callers outside the
   *  view (the request card's Approve): resolves true when Garry clicks Export all / Approve, false otherwise. o: {title,
   *  yes}: the words on the button; with nothing staged the box says so and resolves on the plain button. */
  async function confirmBox(kind, id, code, o) {
    const opts = o || {};
    const b = await fetchJson(`${base(kind, id, code)}/batch`, null);
    return new Promise((resolve) => {
      const dlg = document.createElement('dialog');
      dlg.className = 'sp-modal fr-batch-modal';
      const done = (v) => { try { dlg.close(); } catch (_) { /* closed */ } resolve(v); };
      dlg.addEventListener('close', () => { dlg.remove(); resolve(false); });
      const items = b && b.ok && Array.isArray(b.items) ? b.items : [];
      dlg.appendChild(el('div', { class: 'sp-modal-head' }, el('b', { text: opts.title || `${id} · ${code}: confirm the batch` }), el('span', { class: 'spacer' }), el('button', { type: 'button', class: 'btn small', text: '✕', onclick: () => done(false) })));
      if (items.length) dlg.appendChild(batchContent(b));
      else dlg.appendChild(el('p', { class: 'muted small', text: b && b.error ? b.error : `nothing is staged for ${code}: ${opts.empty || 'approving installs nothing new in the strip'}` }));
      dlg.appendChild(el('div', { class: 'row', style: 'display:flex; gap:8px; margin-top:8px;' },
        el('button', { type: 'button', class: 'btn small primary', text: opts.yes || (items.length ? `Export all ${items.length} (one click for the whole batch)` : 'Approve'), onclick: () => done(true) }),
        el('button', { type: 'button', class: 'btn small ghost', text: 'Cancel', onclick: () => done(false) })));
      document.body.appendChild(dlg);
      dlg.showModal();
    });
  }

  return { open, summary, HELP, confirmBox, batchContent };
})();
if (typeof module !== 'undefined') module.exports = Frames;
