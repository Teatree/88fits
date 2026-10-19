// The driver library (pass 93, lane PREVIEW). Garry: "I only see names and can't tell what the actual animation will
// look like ... this preview should also include the frame index somewhere." Three parts:
//
//   Drivers.render(panel)   the Drivers tab: every folder of tools/dl/drivers (/api/drivers, drivers_io.py) as a card
//                           (hover to play, what made it, the frames per view, its date and size, the looks that use
//                           it), searchable, filtered by kind, sorted; a click opens the viewer.
//   Drivers.open(name, o)   the viewer, a <dialog>: one view at a time (tabs), the frame big with its index on it (the
//                           number in the file name, 0-based: death_keep's numbers), play / pause, step, first / last,
//                           a scrub bar, the speed, loop on or off, the clay and look stills beside it, every frame as a
//                           numbered contact sheet, the folder's path with Copy and Open folder, meta.json, who uses it.
//                           With o.pick ({list, onChange, dflt, painted}) the contact sheet toggles frames into the list
//                           (death_keep), "Play the kept frames" plays them as the result would, and a look's painted
//                           death (tools/dl/ai_anim/<key>_death/full_NN.png) can stand in for the depth frames.
//   Drivers.thumb(name, o)  a field's inline preview: a small frame that plays while the mouse is over it + "preview".
//   Drivers.keepField(o)    the death_keep control: the list typed or picked, the kept frames as small numbered tiles.
//
// One clock per open viewer (requestAnimationFrame, stopped when it closes); thumbs play only while hovered. The maths
// live in drivers_model.js (DriversModel), checked under Node by selftest_PREVIEW93.py.
'use strict';

const Drivers = (() => {
  const DM = DriversModel;
  const el = (...a) => U.el(...a);
  const ROOT_HELP = 'Drivers are kept in tools/dl/drivers/<name>/ (one folder per driver), with a folder per view inside: front, fd (front ¾), side, bd (back ¾), back. '
    + 'In a view folder, driver_00.png, driver_01.png … are OpenPose stick figures (the heroes\' and humanoid creatures\' walks, made from a Mixamo FBX by tools/pose_driver.py); '
    + 'ctl_00.png, ctl_01.png … are depth frames of a 3D model (the creatures\' walks and deaths, made in Blender: light = near, dark = far); '
    + 'clay.png is the model standing in grey clay, look.png the model in its own colours, clay_NN.png a one-shot\'s clay at frame NN. '
    + 'meta.json says what made it; <view>_sheet.png and all_sheet.png are contact sheets. The frame index is the number in the file name, starting at 0: '
    + 'death_keep\'s numbers are these. Any picture viewer opens them (Windows Photos steps through a folder with the arrow keys).';
  const S = { list: null, loading: null, failed: false, details: {}, painted: {}, q: '', kind: 'all', sort: 'name', panel: null };

  // ------------------------------------------------------------------ data

  async function fetchJson(url, dflt) {
    try { const r = await fetch(url, { cache: 'no-store' }); if (!r.ok) return dflt; return await r.json(); } catch (_) { return dflt; }
  }
  /** The listing (/api/drivers), fetched once; `force` fetches it again. */
  function ensureList(force) {
    if (S.list && !force) return Promise.resolve(S.list);
    if (S.loading && !force) return S.loading;
    S.loading = fetchJson('/api/drivers', null).then((r) => {
      S.loading = null;
      if (!Array.isArray(r)) { S.failed = true; return S.list || []; }
      S.failed = false;
      S.list = r;
      if (force) S.details = {};
      return r;
    });
    return S.loading;
  }
  function byName(name) { return Array.isArray(S.list) ? S.list.find((d) => d.name === name) || null : null; }
  /** One driver with every frame and still (/api/drivers/<name>). */
  async function detail(name, force) {
    if (!name) return null;
    if (S.details[name] && !force) return S.details[name];
    const r = await fetchJson('/api/drivers/' + encodeURIComponent(name), null);
    if (r && r.ok) S.details[name] = r;
    return r && r.ok ? r : null;
  }
  /** A creature_ctl look's painted death (tools/dl/ai_anim/<enemy>_<code>_death), cached for 20 s. */
  async function painted(enemy, code) {
    if (!enemy || !code) return null;
    const k = `${enemy}/${code}`;
    const hit = S.painted[k];
    if (hit && Date.now() - hit.t < 20000) return hit.r;
    const r = await fetchJson(`/api/painted_death/${encodeURIComponent(enemy)}/${encodeURIComponent(code)}`, null);
    S.painted[k] = { t: Date.now(), r };
    return r;
  }

  function copyText(text, what) {
    const done = () => { if (typeof App !== 'undefined' && App.status) App.status(`copied ${what || 'the path'}: ${text}`, 'good'); };
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) { navigator.clipboard.writeText(text).then(done, () => fallbackCopy(text, done)); return; }
    } catch (_) { /* below */ }
    fallbackCopy(text, done);
  }
  function fallbackCopy(text, done) {
    const ta = el('textarea', { style: 'position:fixed;left:-9999px;top:0' });
    ta.value = text;
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand('copy'); done(); } catch (_) { /* nothing more to do */ }
    ta.remove();
  }
  async function openFolder(name, view) {
    try {
      const url = name ? `/api/drivers/${encodeURIComponent(name)}/open` : '/api/drivers/open';
      const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(view ? { view } : {}) });
      const j = await r.json().catch(() => ({}));
      if (typeof App !== 'undefined' && App.status) App.status(j.ok ? `opened ${j.path} in Explorer` : `could not open the folder: ${j.error || r.status}`, j.ok ? 'good' : 'bad');
    } catch (e) {
      if (typeof App !== 'undefined' && App.status) App.status(`could not open the folder: ${e}`, 'bad');
    }
  }
  function pathLine(path, name, view) {
    return el('span', { class: 'drv-path' },
      el('code', { text: path, title: 'the folder, relative to the repo (D:/_projects/88fits)' }),
      el('button', { type: 'button', class: 'btn small', text: 'Copy path', title: 'copy the folder\'s path', onclick: (e) => { e.stopPropagation(); copyText(path); } }),
      name ? el('button', { type: 'button', class: 'btn small', text: 'Open folder', title: 'open it in Explorer (the server opens it on this PC)', onclick: (e) => { e.stopPropagation(); openFolder(name, view); } }) : null);
  }

  // ------------------------------------------------------------------ the inline thumb (hover plays)

  /** A small frame of driver `name`'s view that plays while the mouse is over it, its index in the corner, and a
   *  "preview" button that opens the viewer on that view. o: {view, size (48), label, onPreview}. */
  function hoverFrames(d, view, size) {
    const n = d.counts && d.counts[view] != null ? Number(d.counts[view]) : Number(d.frames) || 0;
    const first = d.first && d.first[view] != null ? Number(d.first[view]) : 0;
    const pat = DM.framePattern(d, view);
    const img = el('img', { class: 'drv-thumb-img', alt: '', loading: 'lazy', src: DM.frameUrl(pat, first), style: `width:${size}px;height:${size}px` });
    const idx = el('span', { class: 'drv-thumb-idx', text: String(first) });
    const box = el('span', { class: 'drv-thumb-box', title: `${d.name} · ${DM.VIEW_LABEL[view] || view} · ${n} frames: hover to play` }, img, idx);
    let timer = null;
    let k = 0;
    box.addEventListener('mouseenter', () => {
      if (timer || n < 2) return;
      timer = setInterval(() => { k = (k + 1) % n; img.src = DM.frameUrl(pat, first + k); idx.textContent = String(first + k); }, 1000 / 12);
    });
    box.addEventListener('mouseleave', () => { if (timer) clearInterval(timer); timer = null; k = 0; img.src = DM.frameUrl(pat, first); idx.textContent = String(first); });
    return box;
  }
  function thumb(name, opts) {
    const o = opts || {};
    const size = Number(o.size) || 44;
    const wrap = el('span', { class: 'drv-thumb' });
    if (!name) { wrap.appendChild(el('span', { class: 'muted small', text: o.emptyText || '' })); return wrap; }
    const fill = () => {
      U.clear(wrap);
      const d = byName(name);
      if (!d) { wrap.appendChild(el('span', { class: 'muted small', text: S.failed ? 'no /api/drivers' : (S.list ? `${name}: not in tools/dl/drivers` : 'loading…') })); return; }
      const view = DM.pickView(d.views, o.view);
      wrap.appendChild(hoverFrames(d, view, size));
      wrap.appendChild(el('button', { type: 'button', class: 'btn small', text: 'preview', title: `the driver ${name}, view ${view}: play it frame by frame, its frame numbers, clay and look`, onclick: (e) => { e.preventDefault(); e.stopPropagation(); open(name, { view }); } }));
    };
    if (S.list) fill(); else { wrap.appendChild(el('span', { class: 'muted small', text: 'loading…' })); ensureList().then(fill); }
    return wrap;
  }

  // ------------------------------------------------------------------ the viewer

  /** The viewer on driver `name`. o: {view, frame, pick: {list, dflt, onChange(list), painted: {enemy, code}, label}}. */
  async function open(name, opts) {
    const o = opts || {};
    const dlg = document.createElement('dialog');
    dlg.className = 'sp-modal drv-modal';
    dlg.appendChild(el('div', { class: 'sp-modal-head' }, el('b', { text: `driver ${name}` }), el('span', { class: 'muted small', text: 'loading…' }), el('span', { class: 'spacer' }), el('button', { type: 'button', class: 'btn small', text: '✕', onclick: () => dlg.close() })));
    document.body.appendChild(dlg);
    let viewer = null;
    dlg.addEventListener('close', () => { if (viewer) viewer.stop(); dlg.remove(); });
    dlg.showModal();
    const d = await detail(name, true);
    if (!dlg.isConnected) return null;
    if (!d) {
      U.clear(dlg);
      dlg.append(el('div', { class: 'sp-modal-head' }, el('b', { text: `driver ${name}` }), el('span', { class: 'spacer' }), el('button', { type: 'button', class: 'btn small', text: '✕', onclick: () => dlg.close() })),
        el('p', { class: 'warn-text', text: `There is no driver ${name}: no folder tools/dl/drivers/${name} with frames in it.` }), el('p', { class: 'muted small', text: ROOT_HELP }));
      return null;
    }
    let paintedRec = null;
    if (o.pick && o.pick.painted) paintedRec = await painted(o.pick.painted.enemy, o.pick.painted.code);
    // a death painted along another driver is not this one's frames
    if (paintedRec && paintedRec.exists && !DM.paintedFits(paintedRec.ctl_dir, name)) paintedRec = Object.assign({}, paintedRec, { exists: false, other: paintedRec.ctl_dir });
    if (!dlg.isConnected) return null;
    viewer = new Viewer(dlg, d, o, paintedRec);
    return viewer;
  }

  class Viewer {
    constructor(dlg, d, o, paintedRec) {
      this.dlg = dlg; this.d = d; this.o = o;
      this.pick = o.pick || null;
      this.keep = this.pick ? (DM.parseList(this.pick.list).list || (Array.isArray(this.pick.dflt) ? this.pick.dflt.slice() : [])) : [];
      this.paintedRec = paintedRec && paintedRec.exists && paintedRec.frames && paintedRec.frames.length ? paintedRec : null;
      this.paintedOther = paintedRec && paintedRec.other ? paintedRec.other : '';
      this.source = this.pick && this.paintedRec ? 'painted' : 'driver';
      this.keptOnly = false;
      this.view = DM.pickView(d.views, o.view);
      this.loop = this.pick ? false : d.plays !== 'once';
      this.fps = 12;
      this.pos = 0;
      this.playing = !this.pick;
      this.raf = 0; this.last = 0; this.acc = 0;
      this.preload = [];
      this.build();
      this.setView(this.view, o.frame);
      this.dlg.addEventListener('keydown', (e) => this.key(e));
    }
    /** The frames the stage plays now: [{i, url}] of the view (or the painted death), only the kept ones when asked. */
    seq() {
      const all = this.allFrames();
      if (!this.keptOnly) return all;
      const at = new Map(all.map((f) => [f.i, f]));
      return DM.playOrder(this.keep, Infinity).map((i) => at.get(i)).filter(Boolean);
    }
    allFrames() {
      if (this.source === 'painted' && this.paintedRec) return this.paintedRec.frames;
      const vd = this.d.view_detail[this.view];
      return vd ? vd.frames : [];
    }
    total() { const a = this.allFrames(); return a.length ? a[a.length - 1].i + 1 : 0; }
    build() {
      const d = this.d;
      U.clear(this.dlg);
      const head = el('div', { class: 'sp-modal-head drv-head' },
        el('b', { class: 'drv-title', text: d.name }),
        el('span', { class: 'drv-kind ' + (d.kind === 'depth' ? 'depth' : 'pose'), text: DM.kindText(d) }),
        el('span', { class: 'muted small', text: `${DM.countsText(d)} · ${DM.sizeText(d.size)} · ${DM.dateText(d.mtime)}` }),
        el('span', { class: 'spacer' }),
        el('button', { type: 'button', class: 'btn small', text: '✕ close', onclick: () => this.dlg.close() }));
      this.tabs = el('div', { class: 'drv-tabs' });
      for (const v of d.views) {
        const b = el('button', { type: 'button', class: 'btn small', text: `${DM.VIEW_LABEL[v] || v} · ${d.counts[v]}`, title: `the ${d.view_detail[v] ? d.view_detail[v].label : v} view: ${d.view_detail[v] ? d.view_detail[v].path : ''}`, onclick: () => this.setView(v) });
        b.dataset.view = v;
        this.tabs.appendChild(b);
      }
      // the stage: the frame, its index big, the file under it
      this.img = el('img', { class: 'drv-frame', alt: '' });
      this.bigIdx = el('div', { class: 'drv-bigidx', title: 'the frame index: the number in the file name (0-based), the number death_keep holds' });
      this.keptMark = el('div', { class: 'drv-keptmark', hidden: true });
      this.fileLine = el('div', { class: 'drv-file muted small' });
      const stage = el('div', { class: 'drv-stage' }, this.img, this.bigIdx, this.keptMark);
      // the controls
      const B = (text, title, fn) => el('button', { type: 'button', class: 'btn small', text, title, onclick: fn });
      this.playBtn = B('▶ play', 'play / pause (Space)', () => (this.playing ? this.pause() : this.play()));
      this.scrub = el('input', { type: 'range', class: 'drv-scrub', min: 0, max: 0, step: 1, value: 0, title: 'drag through the frames' });
      this.scrub.addEventListener('input', () => { this.pause(); this.show(Number(this.scrub.value)); });
      const speed = el('select', { title: 'frames a second (the game plays a creature walk at about 10, a hero run at 14)' });
      for (const f of DM.SPEEDS) speed.appendChild(el('option', { value: f, text: `${f} fps`, selected: f === this.fps }));
      speed.addEventListener('change', () => { this.fps = Number(speed.value) || 12; });
      const loopCb = el('input', { type: 'checkbox' });
      loopCb.checked = this.loop;
      loopCb.addEventListener('change', () => { this.loop = loopCb.checked; });
      const ctl = el('div', { class: 'drv-ctl' },
        B('|◀', 'the first frame (Home)', () => { this.pause(); this.show(0); }),
        B('◀', 'one frame back (←)', () => { this.pause(); this.show(DM.step(this.pos, this.seq().length, -1, true)); }),
        this.playBtn,
        B('▶', 'one frame on (→)', () => { this.pause(); this.show(DM.step(this.pos, this.seq().length, 1, true)); }),
        B('▶|', 'the last frame (End)', () => { this.pause(); this.show(this.seq().length - 1); }),
        this.scrub, speed,
        el('label', { class: 'cb', title: 'off: it plays once and stops on the last frame (as a death plays)' }, loopCb, el('span', { text: 'loop' })));
      // the stills beside it
      this.stills = el('div', { class: 'drv-stills' });
      const main = el('div', { class: 'drv-main' }, el('div', { class: 'drv-left' }, stage, this.fileLine, ctl), this.stills);
      // the picker's bar
      this.pickBar = this.pick ? this.buildPickBar() : null;
      // the contact sheet
      this.sheetHead = el('div', { class: 'drv-sheet-head muted small' });
      this.sheet = el('div', { class: 'drv-sheet' });
      // what made it, where it is, who uses it
      const info = el('div', { class: 'drv-info' });
      info.appendChild(el('div', {}, el('b', { text: 'Made from: ' }), el('span', { text: d.made || '—' })));
      if (d.parent) info.appendChild(el('div', {}, el('b', { text: 'Copy of: ' }), el('a', { href: '#', text: d.parent, onclick: (e) => { e.preventDefault(); this.dlg.close(); open(d.parent, { view: this.view }); } })));
      this.pathBox = el('div', { class: 'drv-pathbox' });
      info.appendChild(this.pathBox);
      const used = Array.isArray(d.used_by) ? d.used_by : [];
      info.appendChild(el('div', {}, el('b', { text: `Used by ${used.length ? used.length : 'no'} look${used.length === 1 ? '' : 's'}${used.length ? ':' : ' (no enemy, boss or hero recipe names it)'} ` }),
        used.map((u) => el('span', { class: 'drv-used' + (u.played ? ' played' : ''), text: DM.usedText(u) }))));
      if (d.has_meta) {
        const det = el('details', { class: 'drv-meta' }, el('summary', { text: 'meta.json (everything the tool recorded)' }), el('pre', { class: 'mono small', text: JSON.stringify(d.meta, null, 1) }));
        info.appendChild(det);
      } else info.appendChild(el('div', { class: 'muted small', text: 'no meta.json in this folder' + (d.parent ? `: ${d.parent}'s describes the model and the clip` : '') }));
      info.appendChild(el('details', { class: 'drv-meta' }, el('summary', { text: 'Where drivers are kept, and which file is what' }), el('p', { class: 'small', text: ROOT_HELP })));
      this.dlg.append(...[head, this.tabs, main, this.pickBar, this.sheetHead, this.sheet, info].filter(Boolean));
    }
    buildPickBar() {
      const p = this.pick;
      const bar = el('div', { class: 'drv-pickbar' });
      this.keepLine = el('span', { class: 'drv-keepline' });
      const keptOnly = el('input', { type: 'checkbox' });
      keptOnly.addEventListener('change', () => { this.keptOnly = keptOnly.checked; this.show(0); this.drawSheet(); if (this.keptOnly) this.play(); });
      this.keptOnlyCb = keptOnly;
      const B = (text, title, fn) => el('button', { type: 'button', class: 'btn small', text, title, onclick: fn });
      const nWant = Array.isArray(p.dflt) && p.dflt.length ? p.dflt.length : 8;
      bar.append(el('b', { text: p.label || 'Frames kept' }), this.keepLine,
        el('label', { class: 'cb', title: 'play only the kept frames, in their order: what the strip\'s death will be' }, keptOnly, el('span', { text: 'play the kept frames (the result)' })),
        B(`even ${nWant}`, `${nWant} frames spread over the clip, the last one in`, () => this.setKeep(DM.evenPick(this.total(), nWant))),
        Array.isArray(p.dflt) ? B('the default', `the method's default: ${p.dflt.join(' ')}`, () => this.setKeep(p.dflt.slice())) : null,
        B('clear', 'keep none (the field empties: the default applies)', () => this.setKeep([])));
      if (this.paintedRec) {
        const sel = el('select', { title: 'what the frames show: the depth driver the death walked along, or what Wan painted along it (every frame, before death_keep picked)' },
          el('option', { value: 'painted', text: `painted death (${this.paintedRec.key})`, selected: this.source === 'painted' }),
          el('option', { value: 'driver', text: 'the depth driver', selected: this.source === 'driver' }));
        sel.addEventListener('change', () => { this.source = sel.value; this.show(Math.min(this.pos, this.seq().length - 1)); this.drawSheet(); this.drawStills(); });
        bar.append(el('label', { class: 'cb' }, el('span', { text: 'show' }), sel));
        if (Array.isArray(this.paintedRec.keep)) bar.append(el('span', { class: 'muted small', text: `the cache was cut with ${this.paintedRec.keep.join(' ')}; a new keep is picked again from it without a render` }));
      } else if (p.painted) bar.append(el('span', { class: 'muted small', text: this.paintedOther ? `${p.painted.enemy} ${p.painted.code}'s painted death was walked along ${this.paintedOther}, not this driver: its depth frames are shown` : `no painted death yet for ${p.painted.enemy} ${p.painted.code} (it appears here once the look's job has run)` }));
      bar.append(el('span', { class: 'muted small', text: 'click a frame below to keep it or drop it' }));
      return bar;
    }
    setKeep(list) {
      this.keep = list.slice();
      if (this.pick && typeof this.pick.onChange === 'function') this.pick.onChange(this.keep.length ? this.keep.slice() : null);
      this.drawKeep();
      this.drawSheet();
      if (this.keptOnly) this.show(Math.min(this.pos, Math.max(0, this.seq().length - 1)));
      else this.show(this.pos);
    }
    drawKeep() {
      if (!this.keepLine) return;
      const c = DM.clamp(this.keep, this.total());
      this.keepLine.textContent = DM.keepText(this.keep, this.pick.dflt) + (c.outside.length ? ` · ${c.outside.join(' ')} past the clip's ${this.total()} frames` : '');
      this.keepLine.classList.toggle('warn-text', c.outside.length > 0);
    }
    setView(v, frame) {
      this.view = v;
      for (const b of this.tabs.children) b.classList.toggle('on', b.dataset.view === v);
      U.clear(this.pathBox);
      const vd = this.d.view_detail[v];
      this.pathBox.append(el('b', { text: 'Folder: ' }), pathLine(this.d.path, this.d.name), el('span', { class: 'muted small', text: ' this view: ' }), pathLine(vd ? vd.path : this.d.path, this.d.name, v));
      const seq = this.seq();
      // pre-load the view's frames once, so playing never flickers
      this.preload = seq.map((f) => { const im = new Image(); im.src = f.url; return im; });
      let at = 0;
      if (frame != null) { const k = seq.findIndex((f) => f.i === Number(frame)); if (k >= 0) at = k; }
      this.drawStills();
      this.drawKeep();
      this.drawSheet();
      this.show(at);
      if (this.playing) this.play();
    }
    drawStills() {
      U.clear(this.stills);
      const vd = this.d.view_detail[this.view];
      const stills = vd ? vd.stills : [];
      this.dlg.classList.toggle('painted', this.source === 'painted' && !!this.paintedRec);
      if (this.source === 'painted' && this.paintedRec) {
        this.stills.appendChild(el('div', { class: 'drv-stills-note' }, el('span', { class: 'muted small', text: `the frames shown are the painted death: Wan painted the look along ${this.d.name}'s front view, every frame kept as full_NN.png in` }), pathLine(this.paintedRec.path, null, null)));
      }
      if (!stills.length) { this.stills.appendChild(el('div', { class: 'muted small', text: this.d.kind === 'depth' ? 'no clay or look still in this view' : 'OpenPose drivers carry no stills: the stick figure is the guide (the sheets below show every frame)' })); return; }
      for (const s of stills) {
        const im = el('img', { src: s.url, alt: s.label, loading: 'lazy', class: /_sheet\.png$/.test(s.file) ? 'wide' : '', title: `${s.file}: click to see it large` });
        im.addEventListener('click', () => StripPlayer.openImage(s.url, `${this.d.name} · ${this.view} · ${s.file}`));
        this.stills.appendChild(el('figure', { class: 'drv-still' }, im, el('figcaption', { text: s.label })));
      }
    }
    drawSheet() {
      U.clear(this.sheet);
      const all = this.allFrames();
      const keepPos = new Map(this.keep.map((i, k) => [i, k]));
      this.sheetHead.textContent = this.pick
        ? `${all.length} frames (${this.source === 'painted' ? 'painted' : 'depth'}), numbered as the files are: click to keep or drop; the small number is its place in the kept order`
        : `all ${all.length} frames of the ${DM.VIEW_LABEL[this.view] || this.view} view, numbered as the files are (${all.length ? all[0].file || '' : ''} …): click one to show it`;
      this.cells = new Map();
      for (const f of all) {
        const kept = keepPos.has(f.i);
        const c = el('button', { type: 'button', class: 'drv-cell' + (kept ? ' kept' : ''), title: this.pick ? `frame ${f.i}: ${kept ? 'kept (click to drop)' : 'click to keep'}` : `frame ${f.i}: show it` },
          el('img', { src: f.url, alt: '', loading: 'lazy' }), el('span', { class: 'drv-cell-idx', text: String(f.i) }),
          kept ? el('span', { class: 'drv-cell-order', text: `#${keepPos.get(f.i) + 1}` }) : null);
        c.addEventListener('click', () => {
          if (this.pick) { this.setKeep(DM.toggle(this.keep, f.i)); return; }
          this.pause();
          const k = this.seq().findIndex((x) => x.i === f.i);
          if (k >= 0) this.show(k);
        });
        this.cells.set(f.i, c);
        this.sheet.appendChild(c);
      }
    }
    show(k) {
      const seq = this.seq();
      const n = seq.length;
      this.scrub.max = String(Math.max(0, n - 1));
      if (!n) { this.img.removeAttribute('src'); this.bigIdx.textContent = '–'; this.fileLine.textContent = this.keptOnly ? 'no frames kept' : 'no frames'; this.keptMark.hidden = true; return; }
      this.pos = Math.max(0, Math.min(n - 1, Number(k) || 0));
      const f = seq[this.pos];
      this.img.src = f.url;
      this.bigIdx.textContent = String(f.i);
      this.scrub.value = String(this.pos);
      const total = this.allFrames().length;
      this.fileLine.textContent = this.keptOnly
        ? `kept frame ${this.pos + 1} of ${n} · frame ${f.i} · ${f.url.split('/').pop().split('?')[0]}`
        : `frame ${f.i} · ${this.pos + 1} of ${total} · ${f.url.split('/').pop().split('?')[0]}`;
      const kp = this.pick ? this.keep.indexOf(f.i) : -1;
      this.keptMark.hidden = kp < 0;
      this.keptMark.textContent = kp >= 0 ? `kept #${kp + 1}` : '';
      if (this.cells) for (const [i, c] of this.cells) c.classList.toggle('cur', i === f.i);
    }
    play() {
      this.playing = true;
      this.playBtn.textContent = '❚❚ pause';
      if (!this.loop && this.pos >= this.seq().length - 1) this.show(0);
      if (!this.raf) { this.last = performance.now(); this.acc = 0; this.raf = requestAnimationFrame((t) => this.tick(t)); }
    }
    pause() { this.playing = false; this.playBtn.textContent = '▶ play'; if (this.raf) cancelAnimationFrame(this.raf); this.raf = 0; }
    stop() { this.pause(); this.preload = []; }
    tick(t) {
      this.raf = 0;
      if (!this.playing || !this.dlg.isConnected) return;
      this.acc += Math.min(0.25, (t - this.last) / 1000);
      this.last = t;
      const per = 1 / this.fps;
      const n = this.seq().length;
      while (this.acc >= per && n > 1) {
        this.acc -= per;
        if (!this.loop && this.pos >= n - 1) { this.show(n - 1); this.pause(); return; }
        this.show(DM.step(this.pos, n, 1, true));
      }
      this.raf = requestAnimationFrame((t2) => this.tick(t2));
    }
    key(e) {
      const t = e.target;
      const tag = t && t.tagName;
      if ((tag === 'INPUT' && !['range', 'checkbox'].includes(t.type)) || tag === 'TEXTAREA' || tag === 'SELECT') return;
      const n = this.seq().length;
      if (e.key === ' ') { e.preventDefault(); this.playing ? this.pause() : this.play(); }
      else if (e.key === 'ArrowRight') { e.preventDefault(); this.pause(); this.show(DM.step(this.pos, n, 1, true)); }
      else if (e.key === 'ArrowLeft') { e.preventDefault(); this.pause(); this.show(DM.step(this.pos, n, -1, true)); }
      else if (e.key === 'Home') { e.preventDefault(); this.pause(); this.show(0); }
      else if (e.key === 'End') { e.preventDefault(); this.pause(); this.show(n - 1); }
      else return;
      e.stopPropagation();
    }
  }

  // ------------------------------------------------------------------ death_keep: the field

  /** The frame-list control (death_keep). o: {value, onChange(list|null), driver (the death driver's name, own or
   *  inherited), driverNote, view ('front'), dflt, painted {enemy, code}, label}. */
  function keepField(o) {
    const wrap = el('div', { class: 'drv-keep' });
    let list = DM.parseList(o.value).list;
    const inp = el('input', { type: 'text', class: 'txt', placeholder: Array.isArray(o.dflt) ? `${o.dflt.join(', ')} (the default)` : 'frame numbers', title: 'the frame numbers to keep, as the files are numbered (0 = ctl_00.png): typed (1, 4, 7) or picked' });
    inp.value = Array.isArray(list) ? list.join(', ') : '';
    const err = el('span', { class: 'warn-text small', hidden: true });
    const tiles = el('div', { class: 'drv-keep-tiles' });
    const commit = (next) => {
      list = next && next.length ? next.slice() : null;
      inp.value = list ? list.join(', ') : '';
      err.hidden = true;
      o.onChange(list);
      drawTiles();
    };
    inp.addEventListener('change', () => {
      const r = DM.parseList(inp.value);
      if (r.error) { err.textContent = r.error; err.hidden = false; return; }
      commit(r.list);
    });
    // the driver may change in a form that is not drawn again (the job form): `getDriver` reads it when it is needed
    const drv = () => String((typeof o.getDriver === 'function' ? o.getDriver() : o.driver) || '');
    const from = el('div', { class: 'muted small' });
    const pickBtn = el('button', { type: 'button', class: 'btn small', text: 'Pick frames…',
      title: 'the frames of the death driver (and the painted death when there is one), numbered: click to keep',
      onclick: () => {
        if (!drv()) { if (typeof App !== 'undefined' && App.status) App.status('set the death drivers first: their frames are what you pick from', 'bad'); drawTiles(); return; }
        open(drv(), { view: o.view || 'front', pick: { list: list || (Array.isArray(o.dflt) ? o.dflt.slice() : []), dflt: o.dflt, painted: o.painted, label: o.label || 'Death frames kept', onChange: (l) => commit(l) } });
      } });
    const reset = el('button', { type: 'button', class: 'btn small ghost', text: '↺ default', title: 'empty: the method\'s default applies', onclick: () => commit(null) });
    wrap.append(el('div', { class: 'drv-keep-row' }, inp, pickBtn, reset, err), from, tiles);
    let paintedRec = null;
    async function drawTiles() {
      U.clear(tiles);
      const name = drv();
      from.textContent = name ? `frames of ${name}${o.driverNote ? ' (' + o.driverNote + ')' : ''}` : 'no death drivers set: this list is not read (a dead still is painted instead)';
      const shown = list || (Array.isArray(o.dflt) ? o.dflt : []);
      if (!name || !shown.length) return;
      const d = byName(name) || (await ensureList()).find((x) => x.name === name);
      if (!d) { tiles.appendChild(el('span', { class: 'muted small', text: `${name}: not in tools/dl/drivers` })); return; }
      const view = DM.pickView(d.views, o.view || 'front');
      const pat = DM.framePattern(d, view);
      const total = d.counts && d.counts[view] != null ? d.counts[view] : d.frames;
      const at = paintedRec && paintedRec.exists && DM.paintedFits(paintedRec.ctl_dir, name) ? new Map(paintedRec.frames.map((f) => [f.i, f.url])) : null;
      for (const i of shown) {
        const bad = !(i >= 0 && i < total);
        const src = at && at.has(i) ? at.get(i) : DM.frameUrl(pat, i);
        tiles.appendChild(el('span', { class: 'drv-keep-tile' + (bad ? ' bad' : ''), title: bad ? `frame ${i} is past the clip's ${total} frames` : `frame ${i}${at && at.has(i) ? ' (painted)' : ' (depth)'}` },
          bad ? el('span', { class: 'drv-keep-x', text: '?' }) : el('img', { src, alt: '', loading: 'lazy' }), el('span', { class: 'drv-keep-idx', text: String(i) })));
      }
      tiles.appendChild(el('span', { class: 'muted small', text: `${list ? '' : 'the default · '}${at ? 'painted frames' : 'depth frames'}` }));
    }
    (async () => { if (o.painted) paintedRec = await painted(o.painted.enemy, o.painted.code); drawTiles(); })();
    return wrap;
  }

  // ------------------------------------------------------------------ the Drivers tab

  function render(panel) {
    S.panel = panel;
    U.clear(panel);
    panel.classList.add('drv-page');
    const head = el('div', { class: 'drv-pagehead' },
      el('h2', { text: 'Drivers' }),
      el('p', { class: 'help', text: 'The 3D motions the video model paints over: a driver is a folder of numbered frames per view, and a look\'s recipe names it (pose_drivers, pose, drivers, death_drivers). Hover a card to play it; click it for every frame with its number, the clay and look stills, and the folder.' }),
      el('details', { class: 'drv-where' }, el('summary', { text: 'Where they are kept and how to look at them without the editor' }), el('p', { class: 'small', text: ROOT_HELP }),
        el('div', {}, el('code', { text: 'D:/_projects/88fits/tools/dl/drivers' }), el('button', { type: 'button', class: 'btn small', text: 'Copy path', onclick: () => copyText('D:/_projects/88fits/tools/dl/drivers') }), el('button', { type: 'button', class: 'btn small', text: 'Open folder', onclick: () => openFolder(null) }))));
    const q = el('input', { type: 'search', class: 'txt', placeholder: 'search: a name, a model, a clip, a creature or hero that uses it…', value: S.q });
    const kinds = [['all', 'All'], ['pose', 'OpenPose'], ['depth', 'Depth'], ['death', 'Deaths'], ['used', 'Used by a look'], ['unused', 'Unused']];
    const kindBox = el('span', { class: 'drv-kinds' });
    for (const [k, label] of kinds) kindBox.appendChild(el('button', { type: 'button', class: 'btn small' + (S.kind === k ? ' on' : ''), text: label, onclick: () => { S.kind = k; draw(); for (const b of kindBox.children) b.classList.toggle('on', b.textContent === label); } }));
    const sort = el('select', { title: 'sort by' }, el('option', { value: 'name', text: 'by name', selected: S.sort === 'name' }), el('option', { value: 'date', text: 'newest first', selected: S.sort === 'date' }), el('option', { value: 'size', text: 'biggest first', selected: S.sort === 'size' }));
    const count = el('span', { class: 'muted small' });
    const refresh = el('button', { type: 'button', class: 'btn small', text: 'Refresh', title: 'read the folder again (a driver job that just ended)', onclick: () => { ensureList(true).then(draw); } });
    const bar = el('div', { class: 'drv-bar' }, q, kindBox, sort, count, el('span', { class: 'spacer' }), refresh);
    const grid = el('div', { class: 'drv-lib' });
    panel.append(head, bar, grid);
    q.addEventListener('input', () => { S.q = q.value; draw(); });
    sort.addEventListener('change', () => { S.sort = sort.value; draw(); });
    function draw() {
      U.clear(grid);
      if (!S.list) { grid.appendChild(el('p', { class: 'muted', text: S.failed ? 'no /api/drivers: is the server new enough (pass 93)?' : 'loading the drivers…' })); return; }
      const shown = DM.sort(DM.filter(S.list, S.q, S.kind), S.sort);
      count.textContent = `${shown.length} of ${S.list.length}`;
      for (const d of shown) grid.appendChild(card(d));
      if (!shown.length) grid.appendChild(el('p', { class: 'muted', text: 'nothing matches' }));
    }
    draw();
    ensureList().then(draw);
  }
  function card(d) {
    const view = DM.pickView(d.views, 'side');
    const c = el('div', { class: 'drv-libcard', tabindex: 0, title: `${d.name}: click to open the viewer` });
    c.addEventListener('click', () => open(d.name, { view }));
    c.addEventListener('keydown', (e) => { if (e.key === 'Enter') open(d.name, { view }); });
    // one chip per look (a look naming it for several views or fields lists them in the chip's title)
    const looks = new Map();
    for (const u of Array.isArray(d.used_by) ? d.used_by : []) {
      const k = `${u.kind}/${u.id}/${u.code}`;
      if (looks.has(k)) looks.get(k).key += `, ${u.key}`; else looks.set(k, Object.assign({}, u));
    }
    const used = Array.from(looks.values());
    const usedBox = el('div', { class: 'drv-usedbox' });
    for (const u of used.slice(0, 4)) usedBox.appendChild(el('span', { class: 'drv-used' + (u.played ? ' played' : ''), text: `${u.id}${u.code ? ' ' + u.code : ''}`, title: DM.usedText(u) }));
    if (used.length > 4) usedBox.appendChild(el('span', { class: 'muted small', text: `+${used.length - 4}` }));
    if (!used.length) usedBox.appendChild(el('span', { class: 'muted small', text: 'no look uses it' }));
    const still = d.kind === 'depth' && d.sheets && d.sheets[view] && /clay\.png$/.test(d.sheets[view]) ? el('img', { class: 'drv-libclay', src: d.sheets[view], alt: '', loading: 'lazy', title: 'clay.png: the model standing' }) : null;
    c.append(
      el('div', { class: 'drv-libtop' }, hoverFrames(d, view, 120), still),
      el('div', { class: 'drv-libname' }, el('b', { text: d.name }), el('span', { class: 'drv-kind ' + (d.kind === 'depth' ? 'depth' : 'pose'), text: DM.kindText(d) })),
      el('div', { class: 'muted small', text: DM.countsText(d) }),
      el('div', { class: 'small drv-made', text: d.made || '' }),
      el('div', { class: 'muted small', text: `${DM.dateText(d.mtime)} · ${DM.sizeText(d.size)}${d.plays === 'once' ? ' · plays once' : ' · loops'}` }),
      usedBox);
    return c;
  }

  return { render, open, thumb, keepField, ensureList, detail, painted, byName, copyText, ROOT_HELP, S };
})();
if (typeof module !== 'undefined') module.exports = Drivers;
