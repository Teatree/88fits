// The animated strip preview (pass 66, lane V): a creature's or a hero's sprite strip played on a canvas as the game
// plays it, with a choice of animation (idle, run, attack, hit, die, cheer) and of facing direction (front, back, the
// side and the two three-quarter views, each heading right or left), speed, zoom 1x/2x/4x, a sand backdrop with a 1 m
// bar, and a <dialog> modal for the close look Garry asked for ("every type of animation, every icon, zoomed in, looked
// at in detail"). Garry: "I don't really want to see 100 animations happening at once": one requestAnimationFrame loop
// drives every player on the page, a player ticks only while it is on screen (IntersectionObserver, 100 px margin),
// playing and within the hard cap MAX_ANIMATING = 12 (the rest sit at frame 0 with a "paused: 12 already playing" tag
// and resume as others leave the screen); grid cards use `hover` mode (frame 0, plays while the mouse is over it).
// Decoded strips live in an LRU of at most LRU_MAX = 16 (a hero strip is 15872x768 RGBA, 47 MB decoded): a strip is
// released when its player leaves the screen and decoded again on re-entry.
//
// The maths follow the game: the strip order EnemyDef.frame_offset / Player.gd:165 (AssetsModel's copies are used when
// lane P's module carries them), frame k at ((k % cols) * frame_px, floor(k / cols) * frame_px) with cols = strip_cols
// or the total (artkit.pack_strip, EnemyManager.strip_frames), a missing view key walks Player.gd:965's fallback chain
// (`_anim_for`) and the control says which view really plays, mirroring follows EnemyManager._face_bit (side and
// diagonal sets mirror when heading left; a creature's front and back sets too, inverted by front_faces / back_faces
// "left", never for "straight"; a hero's base and front views never). Rates are preview rates (the game walks at
// fps.run x pace and stands at 3 fps): enemy run fps.run || 10, die fps.die || 6, idle 6, attack 8, hit 8; hero run
// fps.run || 14, hit fps.hit || 12, die fps.die || 8, idle / cheer 6. The cell is `size` m tall at ~94 px/m (gen_art's
// review sheets; the camera's pixels_per_metre is 90 without a target), labelled "approximate scale"; a hero is 1.9 m.
//
// Also here: SeqPlayer (a sequence of frame files: a driver's driver_NN.png, a depth driver's ctl_NN.png, a clip's
// out_NN.png), IconPreview (an icon at 128 / 64 / 36 px on its rarity plate or round for a hero badge), CutoutPreview
// (the hero's title cut-out, 660x888 at a quarter, 1:1 in the modal) and openImage (any picture in the modal).
// The pure parts (animKey, previewFps, mirror, dirList, frameOffset, cell) run under Node for selftest_V.py: nothing at
// the top level touches the document.
'use strict';

const StripPlayer = (() => {
  const MAX_ANIMATING = 12;
  const LRU_MAX = 16;
  const PPM = 94;
  const HOLD_S = 0.6;                 // a one-shot animation (hit, die, cheer) holds its last frame this long, then loops
  const HERO_SIZE = 1.9;              // Player.gd:165: the hero's quad is 1.9 m tall
  const ENEMY_ORDER = ['idle', 'run', 'attack', 'hit', 'die', 'run_b', 'idle_b', 'run_s', 'idle_s', 'run_bd', 'idle_bd', 'run_fd', 'idle_fd'];
  const CHAR_ORDER = ['idle', 'run', 'turn', 'hit', 'die', 'cheer', 'idle_f', 'run_f', 'idle_s', 'run_s', 'idle_bd', 'run_bd', 'idle_fd', 'run_fd', 'hit_f', 'hit_s', 'hit_bd', 'hit_fd'];
  // the key suffix of each view, per kind: a creature's base set is its front, a hero's base set is his back
  const SUFFIX = { enemy: { front: '', back: '_b', side: '_s', bd: '_bd', fd: '_fd' }, hero: { back: '', front: '_f', side: '_s', bd: '_bd', fd: '_fd' } };
  // Player.gd:965 `_anim_for`: a view the strip lacks falls back along the nearest available one; a creature's strip has
  // no chain in the game (a 2-way strip plays front or back by the travel direction), so its chain ends on the base set
  const CHAIN = {
    hero: { '': [''], '_bd': ['_bd', '_s', ''], '_s': ['_s', '_bd', '_fd', ''], '_fd': ['_fd', '_s', '_f'], '_f': ['_f', '_fd', ''] },
    enemy: { '': [''], '_b': ['_b', ''], '_s': ['_s', ''], '_bd': ['_bd', '_b', ''], '_fd': ['_fd', ''] },
  };
  // animations painted once, in the base set only (EnemyDef: attack/hit/die face the viewer; Player: die/cheer/turn)
  const BASE_ONLY = { enemy: ['attack', 'hit', 'die'], hero: ['die', 'cheer', 'turn'] };
  const BASE_ANIMS = { enemy: ['idle', 'run', 'attack', 'hit', 'die'], hero: ['idle', 'run', 'turn', 'hit', 'die', 'cheer'] };
  const LOOPS = ['idle', 'run', 'turn', 'attack'];                       // BillboardSprite.LOOPS; the others hold their last frame
  const VIEW_OF_SUFFIX = { enemy: { '': 'front', '_b': 'back', '_s': 'side', '_bd': 'bd', '_fd': 'fd' }, hero: { '': 'back', '_f': 'front', '_s': 'side', '_bd': 'bd', '_fd': 'fd' } };
  const VIEW_LABEL = { front: 'front', back: 'back', side: 'side', bd: 'back ¾', fd: 'front ¾' };
  // W.gd:37 RARITY_PLATE (the game's five plate colours); /api/vocab's rarity_plate wins when the page has it
  const RARITY_PLATE = { common: '#d2cfc7', uncommon: '#8cc97a', rare: '#6b9fd8', epic: '#a585c8', legendary: '#e0a060' };

  // ------------------------------------------------------------------ pure maths (Node-testable)

  function kindOf(kind) { return kind === 'hero' || kind === 'character' ? 'hero' : 'enemy'; }
  function model() { return typeof AssetsModel !== 'undefined' ? AssetsModel : null; }
  function order(kind) {
    const m = model();
    if (m && Array.isArray(m.ENEMY_ORDER) && Array.isArray(m.CHAR_ORDER)) return kindOf(kind) === 'hero' ? m.CHAR_ORDER : m.ENEMY_ORDER;
    return kindOf(kind) === 'hero' ? CHAR_ORDER : ENEMY_ORDER;
  }
  /** The first frame of `anim` in a strip packed in `ord` with these counts; -1 when the strip has no such animation. */
  function frameOffset(anims, anim, ord) {
    const m = model();
    if (m && typeof m.frameOffset === 'function') return m.frameOffset(anims, anim, ord);
    let off = 0;
    for (const a of ord) { if (a === anim) return off; off += (anims && anims[a] > 0) ? Number(anims[a]) : 0; }
    return -1;
  }
  function totalFrames(anims) {
    const m = model();
    if (m && typeof m.totalFrames === 'function') return m.totalFrames(anims);
    let n = 0; for (const k in (anims || {})) n += anims[k] > 0 ? Number(anims[k]) : 0; return n;
  }
  /** [x, y] in strip pixels of frame k (cols 0 = one row). */
  function cell(k, cols, framePx) {
    const m = model();
    if (m && typeof m.cell === 'function') { const c = m.cell(k, cols, framePx); return Array.isArray(c) ? c : [c.x, c.y]; }
    const c = cols > 0 ? cols : Math.max(1, k + 1);
    return [(k % c) * framePx, Math.floor(k / c) * framePx];
  }
  /** The strip key (anim, dir) plays: {key, suffix, asked, fell, view, ok}. `fell` = another view stands in (the control
   *  says "(plays back view)"); `ok` false = the strip has no frames for it at all. */
  function animKey(kind, anims, anim, dir) {
    const k = kindOf(kind);
    const base = String(anim || 'idle');
    const has = (key) => !!(anims && anims[key] > 0);
    if (BASE_ONLY[k].includes(base) || !dir) return { key: base, suffix: '', asked: '', fell: false, view: VIEW_OF_SUFFIX[k][''], ok: has(base) };
    const asked = SUFFIX[k][dir] != null ? SUFFIX[k][dir] : '';
    const chain = CHAIN[k][asked] || [asked, ''];
    for (const s of chain) if (has(base + s)) return { key: base + s, suffix: s, asked, fell: s !== asked, view: VIEW_OF_SUFFIX[k][s], ok: true };
    return { key: base + asked, suffix: asked, asked, fell: false, view: VIEW_OF_SUFFIX[k][asked], ok: false };
  }
  /** Frames per second the preview plays `anim` at (a preview rate: the game walks at fps.run x pace and stands at 3). */
  function previewFps(kind, anim, fps) {
    const f = fps || {};
    const base = String(anim || '').split('_')[0];
    const num = (key) => { const v = Number(f[key]); return isFinite(v) && v > 0 ? v : 0; };
    if (kindOf(kind) === 'hero') {
      if (num(base)) return num(base);                 // BillboardSprite._speed matches the fps keys by prefix
      return { run: 14, hit: 12, die: 8, turn: 8 }[base] || 6;
    }
    if (base === 'run') return num('run') || 10;      // EnemyManager: run_fps if > 0 else 10
    if (base === 'die') return num('die') || 6;       // die_fps default 6
    return { attack: 8, hit: 8 }[base] || 6;
  }
  /** Is the drawn frame mirrored? EnemyManager._face_bit: side and diagonal sets mirror when heading left; a creature's
   *  front and back sets too, inverted by front_faces / back_faces "left", never for "straight"; a hero's base and front
   *  views never (Player mirrors only its side and diagonal views). */
  function mirror(kind, view, facing, frontFaces, backFaces) {
    const left = facing === 'left';
    if (view === 'side' || view === 'bd' || view === 'fd') return left;
    if (kindOf(kind) === 'hero') return false;
    const faces = String(view === 'back' ? (backFaces || 'right') : (frontFaces || 'right'));
    if (faces === 'left') return !left;
    if (faces === 'straight') return false;
    return left;
  }
  /** The direction choices: 2 (front, back) for a strip without side views, else 8 (five views, the turned ones twice). */
  function dirList(kind, anims) {
    const eight = !!(anims && anims.run_s > 0);        // EnemyManager:814 `eight`; heroes always paint five views
    if (!eight) return [{ v: 'front', dir: 'front', facing: 'right', label: 'front' }, { v: 'back', dir: 'back', facing: 'right', label: 'back' }];
    return [
      { v: 'front', dir: 'front', facing: 'right', label: 'front' },
      { v: 'fd_r', dir: 'fd', facing: 'right', label: 'front ¾ right' },
      { v: 'side_r', dir: 'side', facing: 'right', label: 'side right' },
      { v: 'bd_r', dir: 'bd', facing: 'right', label: 'back ¾ right' },
      { v: 'back', dir: 'back', facing: 'right', label: 'back' },
      { v: 'bd_l', dir: 'bd', facing: 'left', label: 'back ¾ left' },
      { v: 'side_l', dir: 'side', facing: 'left', label: 'side left' },
      { v: 'fd_l', dir: 'fd', facing: 'left', label: 'front ¾ left' },
    ];
  }
  /** The animation choices: the base names with frames, each with its keys per view for the tooltip. */
  function animList(kind, anims) {
    const k = kindOf(kind);
    const out = [];
    for (const base of BASE_ANIMS[k]) {
      const keys = Object.keys(anims || {}).filter((key) => (key === base || key.startsWith(base + '_')) && anims[key] > 0);
      if (!keys.length) continue;
      out.push({ v: base, label: base, count: Number(anims[base] || 0), keys: keys.map((key) => `${key} (${anims[key]})`).join(' · ') });
    }
    return out;
  }
  function viewLabel(view) { return VIEW_LABEL[view] || view; }

  // ------------------------------------------------------------------ the shared clock, the cap, the images

  const players = new Set();
  const images = new Map();           // url -> {url, img, ready, failed, users: Set<player>}
  let rafId = 0;
  let lastNow = 0;
  let io = null;
  let modal = null;                   // {dlg, player, source, wasPlaying}
  const el = (...a) => U.el(...a);

  function prio(p) { return (p.inModal ? 4 : 0) + (p.mode === 'controls' ? 2 : 0) + (p.hovered ? 1 : 0); }

  function loop(now) {
    rafId = 0;
    const dt = lastNow ? Math.min(0.1, (now - lastNow) / 1000) : 0;
    lastNow = now;
    let n = 0;
    let any = false;
    const list = [...players].sort((a, b) => prio(b) - prio(a));
    for (const p of list) {
      if (!p.wants()) { p.active = false; if (p.capped) p.setCapped(false); continue; }
      any = true;
      if (n < MAX_ANIMATING) { n++; p.active = true; if (p.capped) p.setCapped(false); p.tick(dt); }
      else { p.active = false; if (!p.capped) p.setCapped(true); }
    }
    if (any) rafId = requestAnimationFrame(loop); else lastNow = 0;
  }
  function wake() { if (!rafId && typeof requestAnimationFrame === 'function') rafId = requestAnimationFrame(loop); }

  function observer() {
    if (io || typeof IntersectionObserver === 'undefined') return io;
    io = new IntersectionObserver((entries) => {
      for (const e of entries) { const p = e.target.__sp; if (p) p.setVisible(e.isIntersecting); }
    }, { root: null, rootMargin: '100px' });
    return io;
  }

  function acquire(url, p) {
    let e = images.get(url);
    if (!e) {
      e = { url, img: null, ready: false, failed: false, users: new Set() };
      const img = new Image();
      img.decoding = 'async';
      img.onload = () => { e.ready = true; for (const u of e.users) u.onImage(e); wake(); };
      img.onerror = () => { e.failed = true; for (const u of e.users) u.onImage(e); };
      img.src = url;
      e.img = img;
    } else {
      images.delete(url);              // re-insert: a Map iterates in insertion order, so the oldest comes first
    }
    images.set(url, e);
    e.users.add(p);
    evict();
    return e;
  }
  function release(url, p) { const e = images.get(url); if (e) { e.users.delete(p); evict(); } }
  function evict() {
    if (images.size <= LRU_MAX) return;
    for (const [url, e] of images) {
      if (images.size <= LRU_MAX) break;
      if (e.users.size) continue;      // a player on screen draws from it
      images.delete(url);
      if (e.img) { e.img.onload = null; e.img.onerror = null; e.img.src = ''; e.img = null; }
    }
  }

  function stats() {
    let visible = 0, animating = 0, wanting = 0, capped = 0, hovered = 0;
    for (const p of players) {
      if (p.visible) visible++;
      if (p.active) animating++;
      if (p.wants()) wanting++;
      if (p.capped) capped++;
      if (p.hovered) hovered++;
    }
    let decoded = 0;
    for (const e of images.values()) if (e.ready) decoded++;
    return { players: players.size, visible, animating, wanting, capped, hovered, images: images.size, decoded, cap: MAX_ANIMATING, lru: LRU_MAX };
  }

  // ------------------------------------------------------------------ the strip player

  class Player {
    constructor(opts) {
      const o = Object.assign({}, opts || {});
      this.opts = o;
      this.kind = kindOf(o.kind);
      this.url = String(o.url || '');
      if (o.mtime != null && this.url && !this.url.includes('?')) this.url += '?v=' + encodeURIComponent(o.mtime);
      this.framePx = Number(o.framePx) > 0 ? Number(o.framePx) : (this.kind === 'hero' ? 256 : 128);
      this.anims = o.anims && typeof o.anims === 'object' ? o.anims : {};
      this.stripCols = Number(o.stripCols) > 0 ? Number(o.stripCols) : 0;
      this.fps = o.fps && typeof o.fps === 'object' ? o.fps : {};
      this.size = Number(o.size) > 0 ? Number(o.size) : (this.kind === 'hero' ? HERO_SIZE : 1.5);
      this.frontFaces = o.frontFaces || 'right';
      this.backFaces = o.backFaces || 'right';
      this.shadow = o.shadow && typeof o.shadow === 'object' ? o.shadow : null;
      this.mode = o.mode === 'hover' || o.mode === 'still' ? o.mode : 'controls';
      this.anim = o.anim || 'idle';
      this.dir = o.dir || (this.kind === 'hero' ? 'front' : 'front');
      this.facing = o.facing === 'left' ? 'left' : 'right';
      this.zoom = Number(o.zoom) > 0 ? Number(o.zoom) : 1;
      this.speed = Number(o.speed) > 0 ? Number(o.speed) : 1;
      this.backdrop = o.backdrop === 'none' ? 'none' : 'sand';
      this.ppm = Number(o.ppm) > 0 ? Number(o.ppm) : PPM;
      this.onFrame = typeof o.onFrame === 'function' ? o.onFrame : null;
      this.inModal = !!o.inModal;
      this.label = o.label || '';
      this.playing = this.mode === 'controls' ? o.autoplay !== false : this.mode === 'hover';
      this.visible = false;
      this.hovered = false;
      this.active = false;
      this.capped = false;
      this.destroyed = false;
      this.t = 0;
      this.frameIdx = 0;
      this.entry = null;
      this.resolved = null;
      this.build();
      this.resolve();
      players.add(this);
      const ob = observer();
      if (ob) ob.observe(this.el); else this.setVisible(true);
    }

    // ---- DOM
    build() {
      const fig = el('figure', { class: `sp sp-${this.mode}` + (this.inModal ? ' sp-in-modal' : ''), tabindex: this.mode === 'controls' ? 0 : null });
      fig.__sp = this;
      this.el = fig;
      this.canvas = el('canvas', { class: 'sp-canvas' });
      this.ctx = this.canvas.getContext('2d');
      this.tag = el('span', { class: 'sp-tag', hidden: true });
      this.stage = el('div', { class: 'sp-stage' }, this.canvas, this.tag);
      fig.appendChild(this.stage);
      this.sizeCanvas();
      if (this.mode === 'hover') {
        fig.addEventListener('mouseenter', () => { this.hovered = true; this.t = 0; wake(); });
        fig.addEventListener('mouseleave', () => { this.hovered = false; this.showFrame(0); });
        fig.addEventListener('dblclick', () => this.openModal());
        fig.title = this.label ? `${this.label}: hover to play, double-click for the close look` : 'hover to play, double-click for the close look';
      }
      if (this.mode === 'controls') {
        this.buildControls();
        fig.addEventListener('keydown', (e) => {
          if (e.target !== fig) return;
          if (e.key === ' ') { e.preventDefault(); this.playing ? this.pause() : this.play(); }
          else if (e.key === 'ArrowLeft') { e.preventDefault(); this.step(-1); }
          else if (e.key === 'ArrowRight') { e.preventDefault(); this.step(1); }
        });
      }
    }

    sizeCanvas() {
      const px = Math.max(16, Math.round(this.size * this.ppm * this.zoom));
      this.canvas.width = px;
      this.canvas.height = px;
      this.canvas.style.width = px + 'px';
      this.canvas.style.height = px + 'px';
    }

    buildControls() {
      const bar = el('div', { class: 'sp-bar' });
      this.bar = bar;
      // animation
      this.animSel = el('select', { class: 'sp-sel sp-anim', title: 'the animation' });
      this.animSel.addEventListener('change', () => this.setAnim(this.animSel.value));
      // direction (view + heading)
      this.dirSel = el('select', { class: 'sp-sel sp-dir', title: 'the view: which way the figure faces and heads' });
      this.dirSel.addEventListener('change', () => { const d = dirList(this.kind, this.anims).find((x) => x.v === this.dirSel.value); if (d) { this.dir = d.dir; this.facing = d.facing; this.resolve(); this.draw(); this.updateLine(); } });
      // heading left (a 2-way creature strip mirrors its front and back when heading left)
      this.leftCb = el('input', { type: 'checkbox', title: 'heading screen-left: the game mirrors the front and back sets of a creature (EnemyDef.front_faces / back_faces say which way the painting turns)' });
      this.leftCb.addEventListener('change', () => this.setFacing(this.leftCb.checked ? 'left' : 'right'));
      this.leftWrap = el('label', { class: 'sp-cb' }, this.leftCb, el('span', { text: '⇋ left' }));
      // transport
      this.stepBack = el('button', { type: 'button', class: 'btn small sp-btn', text: '◀', title: 'one frame back (←)', onclick: () => this.step(-1) });
      this.playBtn = el('button', { type: 'button', class: 'btn small sp-btn sp-play', text: '▶', title: 'play / pause (space)', onclick: () => (this.playing ? this.pause() : this.play()) });
      this.stepFwd = el('button', { type: 'button', class: 'btn small sp-btn', text: '▶|', title: 'one frame on (→)', onclick: () => this.step(1) });
      this.scrub = el('input', { type: 'range', class: 'sp-scrub', min: 0, max: 0, step: 1, value: 0, title: 'scrub the frames' });
      this.scrub.addEventListener('input', () => { this.pause(); this.seek(Number(this.scrub.value)); });
      // speed
      this.speedSel = el('select', { class: 'sp-sel sp-speed', title: 'playback speed' });
      for (const s of [0.25, 0.5, 1, 2]) this.speedSel.appendChild(el('option', { value: String(s), text: `×${s}`, selected: s === this.speed }));
      this.speedSel.addEventListener('change', () => this.setSpeed(Number(this.speedSel.value)));
      // zoom
      this.zoomBox = el('span', { class: 'sp-zoom' });
      for (const z of [1, 2, 4]) this.zoomBox.appendChild(el('button', { type: 'button', class: 'btn small sp-btn' + (z === this.zoom ? ' on' : ''), text: `${z}×`, 'data-zoom': z, title: `the cell at ${z}× (nearest-neighbour pixels from 1× up)`, onclick: () => this.setZoom(z) }));
      // backdrop
      this.bdBtn = el('button', { type: 'button', class: 'btn small sp-btn', text: this.backdrop === 'sand' ? 'sand' : 'none', title: 'the backdrop: the sand with the foot line, the blob and the 1 m bar, or nothing', onclick: () => this.setBackdrop(this.backdrop === 'sand' ? 'none' : 'sand') });
      // modal
      this.fullBtn = this.inModal ? null : el('button', { type: 'button', class: 'btn small sp-btn', text: '⤢', title: 'the close look: this player at 4× (or as big as fits) in a dialog; Esc closes', onclick: () => this.openModal() });
      bar.append(this.animSel, this.dirSel, this.leftWrap, this.stepBack, this.playBtn, this.stepFwd, this.scrub, this.speedSel, this.zoomBox, this.bdBtn);
      if (this.fullBtn) bar.appendChild(this.fullBtn);
      this.line = el('div', { class: 'sp-line muted small' });
      this.el.append(bar, this.line);
      this.fillSelects();
    }

    fillSelects() {
      if (!this.animSel) return;
      U.clear(this.animSel);
      const al = animList(this.kind, this.anims);
      if (!al.length) this.animSel.appendChild(el('option', { value: 'idle', text: '(no animations)' }));
      for (const a of al) this.animSel.appendChild(el('option', { value: a.v, text: a.label, title: a.keys, selected: a.v === this.anim }));
      U.clear(this.dirSel);
      const dl = dirList(this.kind, this.anims);
      const cur = dl.find((d) => d.dir === this.dir && (d.facing === this.facing || dl.length === 2)) || dl[0];
      for (const d of dl) this.dirSel.appendChild(el('option', { value: d.v, text: d.label, selected: d === cur }));
      this.dirSel.title = dl.length === 8 ? 'eight directions: the strip has side and three-quarter views; the left ones are the right ones mirrored, as the game does' : 'two directions: this strip has front and back sets only; the game picks by the travel direction and mirrors for heading left';
      this.leftWrap.hidden = !(this.kind === 'enemy');
      this.leftCb.checked = this.facing === 'left';
    }

    // ---- state
    resolve() {
      const r = animKey(this.kind, this.anims, this.anim, this.dir);
      const ord = order(this.kind);
      const off = r.ok ? frameOffset(this.anims, r.key, ord) : -1;
      const count = r.ok ? Number(this.anims[r.key] || 0) : 0;
      const base = String(this.anim).split('_')[0];
      this.resolved = { key: r.key, view: r.view, fell: r.fell, ok: r.ok && off >= 0 && count > 0, offset: off, count, fps: previewFps(this.kind, this.anim, this.fps), loops: LOOPS.includes(base), asked: r.asked };
      this.mirrored = mirror(this.kind, r.view, this.facing, this.frontFaces, this.backFaces);
      if (this.frameIdx >= count) this.frameIdx = 0;
      if (this.scrub) { this.scrub.max = Math.max(0, count - 1); this.scrub.value = this.frameIdx; }
      this.updateLine();
    }

    wants() {
      return !this.destroyed && this.playing && this.visible && this.mode !== 'still' && !!(this.entry && this.entry.ready) && (this.mode !== 'hover' || this.hovered) && !!(this.resolved && this.resolved.ok && this.resolved.count > 1);
    }

    tick(dt) {
      const r = this.resolved;
      this.t += dt * this.speed;
      const hold = r.loops ? 0 : HOLD_S;
      const period = r.count / r.fps + hold;
      const tt = this.t % period;
      const idx = Math.min(r.count - 1, Math.floor(tt * r.fps));
      if (idx !== this.frameIdx) this.showFrame(idx, true);
    }

    showFrame(idx, fromTick) {
      this.frameIdx = idx;
      if (!fromTick) this.t = this.resolved && this.resolved.fps ? idx / this.resolved.fps : 0;
      this.draw();
      if (this.scrub) this.scrub.value = idx;
      this.updateCounter();
      if (this.onFrame) this.onFrame(idx, this.resolved);
    }

    setVisible(v) {
      if (this.destroyed) return;
      const was = this.visible;
      this.visible = v;
      if (v) {
        if (this.url && !this.entry) { this.entry = acquire(this.url, this); if (this.entry.ready || this.entry.failed) this.onImage(this.entry); else this.draw(); }
        else if (this.entry && !was) { acquire(this.url, this); }
        wake();
      } else if (this.entry) {
        release(this.url, this);        // the LRU may drop the decoded strip; re-entry decodes it again
        if (!images.has(this.url)) this.entry = null;
      }
      if (!v && this.capped) this.setCapped(false);
    }

    onImage(e) {
      if (e !== this.entry) return;
      if (e.ready) { this.strip = { w: e.img.naturalWidth, h: e.img.naturalHeight }; }
      this.draw();
      this.updateLine();
    }

    setCapped(on) {
      this.capped = on;
      if (on) { this.showFrame(0); this.tag.textContent = `paused: ${MAX_ANIMATING} already playing`; this.tag.hidden = false; }
      else if (this.tag) { this.tag.hidden = true; }
    }

    // ---- drawing
    draw() {
      if (this.destroyed) return;
      const ctx = this.ctx, W = this.canvas.width, H = this.canvas.height;
      ctx.clearRect(0, 0, W, H);
      const e = this.entry;
      if (this.backdrop === 'sand') this.drawSand(ctx, W, H);
      if (!e) { this.note(ctx, W, H, this.url ? '…' : 'no strip'); return; }
      if (e.failed) { this.note(ctx, W, H, 'no strip yet'); return; }
      if (!e.ready) { this.note(ctx, W, H, 'loading…'); return; }
      const r = this.resolved;
      if (!r || !r.ok) { this.note(ctx, W, H, `no ${r ? r.key : this.anim} frames`); return; }
      const cols = this.stripCols || totalFrames(this.anims);
      const [sx, sy] = cell(r.offset + this.frameIdx, cols, this.framePx);
      const scale = W / this.framePx;
      ctx.imageSmoothingEnabled = scale < 1;   // nearest-neighbour from 1× up; a shrunk cell (a grid at 0.5×) is smoothed
      ctx.save();
      if (this.mirrored) { ctx.translate(W, 0); ctx.scale(-1, 1); }
      ctx.drawImage(e.img, sx, sy, this.framePx, this.framePx, 0, 0, W, H);
      ctx.restore();
      if (this.backdrop === 'sand' && this.mode === 'controls') this.drawBar(ctx, W, H);
    }

    drawSand(ctx, W, H) {
      const g = ctx.createRadialGradient(W * 0.5, H * 0.6, 1, W * 0.5, H * 0.6, Math.max(W, H) * 0.75);
      g.addColorStop(0, '#dcc394'); g.addColorStop(0.7, '#c9a874'); g.addColorStop(1, '#b8935e');
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, W, H);
      // the foot line: the quad stands on the ground at the cell's bottom
      ctx.fillStyle = 'rgba(0,0,0,0.28)';
      ctx.fillRect(0, H - 1, W, 1);
      // the blob shadow, approximate (the game drapes an ellipse of the def's `shadow` on the slope)
      const sc = this.shadow && Array.isArray(this.shadow.scale) ? Number(this.shadow.scale[0]) || 1 : 1;
      const rx = W * 0.2 * sc, ry = Math.max(2, rx * 0.28);
      ctx.beginPath();
      ctx.ellipse(W / 2, H - 2, rx, ry, 0, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(40,25,10,0.28)';
      ctx.fill();
    }

    drawBar(ctx, W, H) {
      let metres = 1, px = this.ppm * this.zoom;
      if (px > W - 14) { metres = 0.5; px = px / 2; }
      const x0 = 7, y = H - 9;
      ctx.fillStyle = 'rgba(20,12,4,0.75)';
      ctx.fillRect(x0, y, px, 2);
      ctx.fillRect(x0, y - 4, 1, 10);
      ctx.fillRect(x0 + px - 1, y - 4, 1, 10);
      ctx.font = '10px system-ui, sans-serif';
      ctx.textBaseline = 'alphabetic';
      ctx.fillText(`${metres} m`, x0 + 3, y - 6);
    }

    note(ctx, W, H, text) {
      ctx.fillStyle = 'rgba(0,0,0,0.55)';
      ctx.font = `${Math.max(9, Math.min(12, Math.round(W / 10)))}px system-ui, sans-serif`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(text, W / 2, H / 2, W - 6);
      ctx.textAlign = 'start';
    }

    updateCounter() {
      if (!this.line) return;
      const c = this.line.querySelector('.sp-count');
      if (c && this.resolved) c.textContent = `${this.frameIdx + 1} / ${this.resolved.count}`;
    }

    updateLine() {
      if (!this.line) return;
      const r = this.resolved;
      U.clear(this.line);
      if (!r) return;
      const parts = [];
      parts.push(el('code', { text: r.key }));
      if (r.ok) parts.push(el('span', { text: ` · frames ${r.offset}–${r.offset + r.count - 1} (${r.count}) · ` }), el('span', { class: 'sp-count', text: `${this.frameIdx + 1} / ${r.count}` }), el('span', { text: ` · ${U.fmtN(r.fps, 1)} fps`, title: 'a preview rate: the game walks at fps.run × the map\'s pace and stands at 3 fps; hit, die and cheer play once and hold' }), el('span', { class: 'muted', text: ' (preview rate)' }));
      else parts.push(el('span', { class: 'warn-text', text: ` · the strip has no ${r.key} frames` }));
      if (r.fell) parts.push(el('span', { class: 'warn-text', text: ` · (plays ${viewLabel(r.view)} view${r.asked ? ': no ' + this.anim + r.asked : ''})`, title: 'the strip lacks this view: the game falls back along the nearest available one (Player.gd _anim_for)' }));
      if (this.mirrored) parts.push(el('span', { class: 'muted', text: ' · mirrored' }));
      if (!r.loops && r.ok) parts.push(el('span', { class: 'muted', text: ' · plays once in the game, looped here' }));
      parts.push(el('span', { class: 'muted', text: ` · ${this.size} m at ~${this.ppm} px/m, ${this.zoom}×`, title: 'approximate scale: gen_art\'s review sheets use 94 px/m; the camera\'s pixels_per_metre is 90 without a target' }));
      this.line.append(...parts);
    }

    // ---- the API
    play() { this.playing = true; if (this.playBtn) this.playBtn.textContent = '❚❚'; wake(); return this; }
    pause() { this.playing = false; if (this.playBtn) this.playBtn.textContent = '▶'; return this; }
    seek(k) { const n = this.resolved ? this.resolved.count : 0; if (n <= 0) return this; const idx = Math.max(0, Math.min(n - 1, Math.round(Number(k) || 0))); this.showFrame(idx); return this; }
    step(d) { this.pause(); const n = this.resolved ? this.resolved.count : 0; if (n <= 0) return this; this.showFrame((this.frameIdx + (d > 0 ? 1 : n - 1)) % n); return this; }
    setAnim(a) { this.anim = a || 'idle'; this.frameIdx = 0; this.t = 0; if (this.animSel) this.animSel.value = this.anim; this.resolve(); this.draw(); wake(); return this; }
    setDir(d) { this.dir = d || 'front'; this.resolve(); this.draw(); if (this.dirSel) this.fillSelects(); return this; }
    setFacing(f) { this.facing = f === 'left' ? 'left' : 'right'; this.resolve(); this.draw(); if (this.dirSel) this.fillSelects(); return this; }
    setZoom(z) {
      this.zoom = Number(z) > 0 ? Number(z) : 1;
      this.sizeCanvas();
      if (this.zoomBox) for (const b of this.zoomBox.children) b.classList.toggle('on', Number(b.dataset.zoom) === this.zoom);
      this.draw(); this.updateLine();
      return this;
    }
    setSpeed(s) { this.speed = Number(s) > 0 ? Number(s) : 1; if (this.speedSel) this.speedSel.value = String(this.speed); return this; }
    setBackdrop(b) { this.backdrop = b === 'none' ? 'none' : 'sand'; if (this.bdBtn) this.bdBtn.textContent = this.backdrop; this.draw(); return this; }
    setStrip(o) {
      // another look in the same player (the LookGrid's controls player follows the selected card)
      if (this.entry) { release(this.url, this); this.entry = null; }
      Object.assign(this.opts, o || {});
      this.url = String(this.opts.url || '');
      if (this.opts.mtime != null && this.url && !this.url.includes('?')) this.url += '?v=' + encodeURIComponent(this.opts.mtime);
      this.anims = this.opts.anims && typeof this.opts.anims === 'object' ? this.opts.anims : {};
      this.stripCols = Number(this.opts.stripCols) > 0 ? Number(this.opts.stripCols) : 0;
      this.fps = this.opts.fps && typeof this.opts.fps === 'object' ? this.opts.fps : {};
      this.framePx = Number(this.opts.framePx) > 0 ? Number(this.opts.framePx) : this.framePx;
      this.size = Number(this.opts.size) > 0 ? Number(this.opts.size) : this.size;
      this.frontFaces = this.opts.frontFaces || 'right';
      this.backFaces = this.opts.backFaces || 'right';
      this.shadow = this.opts.shadow && typeof this.opts.shadow === 'object' ? this.opts.shadow : null;
      this.label = this.opts.label || this.label;
      this.frameIdx = 0; this.t = 0;
      this.sizeCanvas();
      if (this.animSel) this.fillSelects();
      this.resolve();
      if (this.visible && this.url) { this.entry = acquire(this.url, this); if (this.entry.ready || this.entry.failed) this.onImage(this.entry); }
      this.draw();
      wake();
      return this;
    }
    openModal() {
      if (this.inModal) return this;
      closeModal();
      const dlg = document.createElement('dialog');
      dlg.className = 'sp-modal';
      const cell1 = Math.max(1, this.size * this.ppm);
      const fit = Math.max(1, Math.min(4, Math.floor((window.innerHeight - 190) / cell1)));
      const p = new Player(Object.assign({}, this.opts, { url: this.url, mode: 'controls', anim: this.anim, dir: this.dir, facing: this.facing, zoom: fit, speed: this.speed, backdrop: this.backdrop, inModal: true, autoplay: false }));
      const title = el('div', { class: 'sp-modal-head' },
        el('b', { text: this.label || (this.kind === 'hero' ? 'hero strip' : 'creature strip') }),
        el('span', { class: 'muted small', text: ` · ${fit}× (${fit === 4 ? 'the close look' : 'as big as fits'}) · Esc closes` }),
        el('span', { class: 'spacer' }),
        el('button', { type: 'button', class: 'btn small', text: '✕ close', onclick: () => dlg.close() }));
      dlg.append(title, p.el);
      document.body.appendChild(dlg);
      const wasPlaying = this.playing;
      this.pause();
      modal = { dlg, player: p, source: this, wasPlaying };
      dlg.addEventListener('close', () => {
        p.destroy();
        dlg.remove();
        if (modal && modal.dlg === dlg) modal = null;
        if (wasPlaying && !this.destroyed) this.play();
      });
      dlg.showModal();
      p.seek(this.frameIdx);
      p.play();
      return this;
    }
    destroy() {
      if (this.destroyed) return;
      this.destroyed = true;
      this.playing = false;
      if (modal && modal.source === this) closeModal();
      if (io) io.unobserve(this.el);
      if (this.entry) release(this.url, this);
      this.entry = null;
      players.delete(this);
      if (this.el.parentNode) this.el.parentNode.removeChild(this.el);
    }
  }

  function closeModal() { if (modal) { const m = modal; modal = null; m.dlg.close(); } }

  // ------------------------------------------------------------------ a sequence of frame files (drivers, clips)

  class SeqPlayer {
    /** opts: {urls} or {pattern: '/dl/drivers/run/front/driver_%02d.png', count, start}, fps (12), size (px), mode
     *  hover | controls | still, label, fit 'contain'. */
    constructor(opts) {
      const o = Object.assign({}, opts || {});
      this.opts = o;
      this.kind = 'seq';
      this.urls = Array.isArray(o.urls) ? o.urls.slice() : [];
      if (!this.urls.length && o.pattern) {
        const n = Number(o.count) || 0, s = Number(o.start) || 0;
        for (let i = 0; i < n; i++) this.urls.push(String(o.pattern).replace(/%0(\d)d/, (m, w) => String(s + i).padStart(Number(w), '0')).replace(/%d/, String(s + i)));
      }
      this.fps = Number(o.fps) > 0 ? Number(o.fps) : 12;
      this.size = Number(o.size) > 0 ? Number(o.size) : 128;
      this.mode = o.mode === 'controls' || o.mode === 'still' ? o.mode : 'hover';
      this.label = o.label || '';
      this.inModal = !!o.inModal;
      this.playing = this.mode !== 'still';
      this.visible = false; this.hovered = false; this.active = false; this.capped = false; this.destroyed = false;
      this.t = 0; this.frameIdx = 0; this.loaded = false; this.ready = 0;
      this.el = el('figure', { class: `sp sp-seq sp-${this.mode}`, title: this.label ? `${this.label}: ${this.urls.length} frames` : `${this.urls.length} frames` });
      this.el.__sp = this;
      this.img = el('img', { class: 'sp-seq-img', alt: '', style: `width:${this.size}px;height:${this.size}px` });
      this.tag = el('span', { class: 'sp-tag', hidden: true });
      this.count = el('span', { class: 'sp-seq-count', text: this.urls.length ? `1 / ${this.urls.length}` : 'no frames' });
      this.el.append(el('div', { class: 'sp-stage' }, this.img, this.tag), this.count);
      if (this.mode === 'hover') {
        this.el.addEventListener('mouseenter', () => { this.hovered = true; this.t = 0; wake(); });
        this.el.addEventListener('mouseleave', () => { this.hovered = false; this.show(0); });
      }
      if (this.mode === 'controls') {
        this.playBtn = el('button', { type: 'button', class: 'btn small sp-btn sp-play', text: '❚❚', onclick: () => (this.playing ? this.pause() : this.play()) });
        this.el.appendChild(el('div', { class: 'sp-bar' }, el('button', { type: 'button', class: 'btn small sp-btn', text: '◀', onclick: () => this.step(-1) }), this.playBtn, el('button', { type: 'button', class: 'btn small sp-btn', text: '▶|', onclick: () => this.step(1) }), el('span', { class: 'muted small', text: `${this.fps} fps` })));
      }
      this.el.addEventListener('dblclick', () => { if (this.urls.length) openImage(this.urls[this.frameIdx], `${this.label || 'frame'} ${this.frameIdx + 1} / ${this.urls.length}`); });
      players.add(this);
      const ob = observer();
      if (ob) ob.observe(this.el); else this.setVisible(true);
    }
    load() {
      if (this.loaded) return;
      this.loaded = true;
      this.frames = this.urls.map((u) => { const im = new Image(); im.decoding = 'async'; im.onload = () => { this.ready++; wake(); }; im.src = u; return im; });
      if (this.urls.length) this.img.src = this.urls[0];
    }
    setVisible(v) { this.visible = v; if (v) { this.load(); wake(); } if (!v && this.capped) this.setCapped(false); }
    wants() { return !this.destroyed && this.playing && this.visible && this.mode !== 'still' && this.urls.length > 1 && (this.mode !== 'hover' || this.hovered) && this.ready >= Math.min(2, this.urls.length); }
    tick(dt) { this.t += dt; const idx = Math.floor(this.t * this.fps) % this.urls.length; if (idx !== this.frameIdx) this.show(idx); }
    show(idx) { this.frameIdx = idx; if (this.urls.length) { this.img.src = this.urls[idx]; this.count.textContent = `${idx + 1} / ${this.urls.length}`; } }
    showFrame(idx) { this.show(idx); }
    setCapped(on) { this.capped = on; if (on) { this.show(0); this.tag.textContent = `paused: ${MAX_ANIMATING} already playing`; this.tag.hidden = false; } else this.tag.hidden = true; }
    play() { this.playing = true; if (this.playBtn) this.playBtn.textContent = '❚❚'; wake(); return this; }
    pause() { this.playing = false; if (this.playBtn) this.playBtn.textContent = '▶'; return this; }
    step(d) { this.pause(); const n = this.urls.length; if (n) this.show((this.frameIdx + (d > 0 ? 1 : n - 1)) % n); return this; }
    destroy() { if (this.destroyed) return; this.destroyed = true; this.playing = false; if (io) io.unobserve(this.el); players.delete(this); this.frames = null; if (this.el.parentNode) this.el.parentNode.removeChild(this.el); }
  }

  // ------------------------------------------------------------------ icons, the title cut-out, any picture in the modal

  function plateFor(rarity) {
    const v = typeof Assets !== 'undefined' && Assets.S && Assets.S.vocab && Assets.S.vocab.rarity_plate;
    const t = v && typeof v === 'object' ? v : RARITY_PLATE;
    return rarity && t[rarity] ? t[rarity] : null;
  }

  /** An icon as the game shows it: the hero sheet's 128 plate, a list size, a HUD size; on its rarity plate (`plate`: a
   *  colour or a rarity name) or round-masked for a hero badge; stripes when the file is not there yet. */
  function IconPreview(url, opts) {
    const o = opts || {};
    const sizes = Array.isArray(o.sizes) && o.sizes.length ? o.sizes : [128, 64, 36];
    const plate = o.plate && !String(o.plate).startsWith('#') ? plateFor(o.plate) : (o.plate || null);
    const names = { 128: 'sheet', 64: 'list', 36: 'HUD' };
    const wrap = el('div', { class: 'icon-preview' + (o.round ? ' round' : '') });
    for (const s of sizes) {
      const box = el('span', { class: 'icon-plate' + (o.round ? ' round' : ''), style: `width:${s}px;height:${s}px;` + (plate ? `background:${plate};` : ''), title: `${s} px${names[s] ? ' · ' + names[s] : ''}${o.plate ? ' · ' + o.plate + ' plate' : ''}` });
      const img = el('img', { src: url, width: s, height: s, alt: '', loading: 'lazy' });
      img.addEventListener('error', () => { box.classList.add('missing'); img.remove(); box.title = 'no icon yet'; });
      img.addEventListener('click', () => openImage(url, `icon · ${url}`));
      box.appendChild(img);
      wrap.appendChild(el('span', { class: 'icon-cell' }, box, el('small', { class: 'muted', text: names[s] ? `${s} · ${names[s]}` : String(s) })));
    }
    return wrap;
  }

  /** The hero's title cut-out (game/art/ui/wanted/hero_<id>.png, 660x888) at a quarter; stripes when it is not there;
   *  ⤢ opens it at 1:1. */
  function CutoutPreview(url) {
    const box = el('div', { class: 'cutout', title: 'the title cut-out, 660 × 888, shown at a quarter' + (typeof LookGrid !== 'undefined' && LookGrid.WHERE_SHOWN ? ' · ' + LookGrid.WHERE_SHOWN.cutout : '') });
    const img = el('img', { src: url, alt: '' });
    img.addEventListener('error', () => { box.classList.add('missing'); img.remove(); box.appendChild(el('span', { class: 'cutout-note', text: 'no title cut-out yet' })); });
    box.appendChild(img);
    box.appendChild(el('button', { type: 'button', class: 'btn small ghost cutout-zoom', text: '⤢', title: 'open at 1:1 (660 × 888)', onclick: () => openImage(url, 'the title cut-out at 1:1 (660 × 888)') }));
    return box;
  }

  /** Any picture in the modal, at 1:1 (scrolls when taller than the window); Esc closes. */
  function openImage(url, caption) {
    closeModal();
    const dlg = document.createElement('dialog');
    dlg.className = 'sp-modal sp-image';
    const img = el('img', { src: url, alt: '' });
    dlg.append(
      el('div', { class: 'sp-modal-head' }, el('b', { text: caption || url }), el('span', { class: 'spacer' }), el('a', { href: url, target: '_blank', class: 'muted small', text: 'open the file' }), el('button', { type: 'button', class: 'btn small', text: '✕ close', onclick: () => dlg.close() })),
      el('div', { class: 'sp-image-box' }, img));
    document.body.appendChild(dlg);
    modal = { dlg, player: null, source: null };
    dlg.addEventListener('close', () => { dlg.remove(); if (modal && modal.dlg === dlg) modal = null; });
    dlg.showModal();
    return dlg;
  }

  function create(opts) { return new Player(opts); }
  function createSeq(opts) { return new SeqPlayer(opts); }

  return {
    create, createSeq, stats, closeModal, openImage, IconPreview, CutoutPreview, plateFor,
    MAX_ANIMATING, LRU_MAX, PPM, HERO_SIZE, RARITY_PLATE, ENEMY_ORDER, CHAR_ORDER, SUFFIX, CHAIN, BASE_ONLY, LOOPS,
    animKey, previewFps, mirror, dirList, animList, frameOffset, totalFrames, cell, order, viewLabel, kindOf,
  };
})();

// the standalone names INTERFACES §7 gives the two picture previews
const IconPreview = StripPlayer.IconPreview;
const CutoutPreview = StripPlayer.CutoutPreview;
if (typeof module !== 'undefined') module.exports = StripPlayer;
