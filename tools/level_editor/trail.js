'use strict';
// Pass 129, lane TRAIL-EDITOR: the Trail tab (game/content/trail/trail.json, docs/trail_schema.md; trail_io.py serves and
// saves it, trail_model.js holds every rule, sum and check). Garry: "Split in 2. On the right side the editing goes ...
// it should be easy to edit those because there's going to be hundreds of these ... On the left side a smaller version
// of the whole Trail as it looks in the game ... a separate scrollable area that I can navigate."
//
// Left: the track as the game lays it out (design width 1080 scaled to the pane), built only for the levels in view, so
// 500 levels cost what ten do. Right: the price curve, the totals, the sections, the upgrade types, the checks, then one
// block per level with one row per node; a block is filled when it nears the view. Every edit is one undo step; a redraw
// puts the caret back in the cell it was in (cells carry data-cell), so Tab and Enter walk the table.
const Trail = (() => {
  const { el, clear, svg } = typeof U !== 'undefined' ? U : {};
  const M = typeof TrailModel !== 'undefined' ? TrailModel : null;
  const store = (k, v) => { try { if (v === undefined) return localStorage.getItem('88fits-trail-' + k); localStorage.setItem('88fits-trail-' + k, v); } catch (_) { /* no storage */ } return null; };
  const S = {
    doc: null, base: null, mtime: null, picks: {}, file: '', failed: null, loading: false, saving: false,
    undo: [], redo: [], sel: null, marked: new Set(), used: new Set(), link: null,
    level: 0, choice: {}, showPrices: store('prices') !== '0',
    order: store('order') === 'low' ? 'low' : 'high', filter: '', onlyIssues: false,
    open: (() => { try { return JSON.parse(store('open') || '') || { price: true, checks: true }; } catch (_) { return { price: true, checks: true }; } })(),
    perRun: Number(store('perrun')) > 0 ? Number(store('perrun')) : 800, d: null, rowH: 34,
  };
  const LISTS = { outlaw: 'outlaws', skin: 'skins', weapon: 'weapons', passive: 'passives', map: 'maps', structure: 'structures', powerup: 'powerups', feature: 'features' };
  const MOTIF_SVG = {
    cactus: '<path d="M27 58V20a5 5 0 0 1 10 0v38zM20 44v-12a3.5 3.5 0 0 0-7 0v14a7 7 0 0 0 7 7h7v-7zM44 40v-12a3.5 3.5 0 0 1 7 0v14a7 7 0 0 1-7 7h-7v-7z"/>',
    star: '<path d="M32 6l7.4 16.4 17.8 2-13.2 12 3.6 17.6L32 45l-15.6 9 3.6-17.6-13.2-12 17.8-2z"/>',
    skull: '<path fill-rule="evenodd" d="M32 8C19 8 10 17 10 29c0 7 3.4 12.6 8.6 16v9h6v-6h4.6v6h5.6v-6h4.6v6h6v-9C50.600 41.6 54 36 54 29 54 17 45 8 32 8zm-8.600 28a5.600 5.600 0 1 1 0-11.200 5.600 5.600 0 0 1 0 11.200zm17.200 0a5.600 5.600 0 1 1 0-11.200 5.600 5.600 0 0 1 0 11.200z"/>',
    horseshoe: '<path d="M14 54V30a18 18 0 0 1 36 0v24h-9V30a9 9 0 0 0-18 0v24z"/>',
    moon: '<path d="M40 8a25 25 0 1 0 16 38A21 21 0 0 1 40 8z"/>',
    flame: '<path d="M32 6c3 12 15 17 15 31a15 15 0 0 1-30 0c0-7 4-10 6-15 1 5 3 7 5 8 0-9 1-17 4-24z"/>',
    dust: '<circle cx="14" cy="20" r="4"/><circle cx="40" cy="12" r="2.500"/><circle cx="50" cy="40" r="5"/><circle cx="24" cy="48" r="3"/>',
  };

  // ------------------------------------------------------------------ data

  function load(force) {
    if (S.loading || (S.doc && !force)) return;
    S.loading = true;
    fetch('/api/trail', { cache: 'no-store' }).then((r) => { if (!r.ok) throw new Error(r.status === 404 ? 'the server has no /api/trail yet: restart the Level Editor (new in pass 129)' : `HTTP ${r.status}`); return r.json(); }).then((d) => {
      if (!d.ok) throw new Error(d.error || 'the Trail could not be read');
      S.picks = d.picks || {}; S.file = d.file || ''; S.mtime = d.mtime;
      S.doc = M.normalise(d.json); S.base = JSON.stringify(d.json == null ? null : M.normalise(d.json));
      S.undo = []; S.redo = []; S.marked = new Set(); S.sel = null; S.link = null; S.failed = null; S.loading = false;
      for (const n of S.doc.nodes) if (n && n.id) S.used.add(n.id);
      derive();
      S.level = Math.min(S.level, S.d.ix.max);
      built = false; scrollLeftBottom = true; redraw();
    }).catch((e) => { S.failed = String(e.message || e); S.loading = false; redraw(); });
  }
  const dirty = () => !!S.doc && JSON.stringify(S.doc) !== S.base;

  function derive() {
    const ix = M.index(S.doc);
    const issues = M.check(S.doc, S.picks);
    const by = new Map(), byLevel = new Map();
    for (const x of issues) {
      if (x.id) { if (!by.has(x.id)) by.set(x.id, []); by.get(x.id).push(x); }
      else if (x.level) { if (!byLevel.has(x.level)) byLevel.set(x.level, []); byLevel.get(x.level).push(x); }
    }
    const st = M.states(S.doc, S.level, S.choice);
    const given = new Map();
    for (const n of ix.nodes) if (n.gives && n.gives.type !== 'upgrade') given.set(n.gives.type + ':' + M.giveWhat(n.gives), n.id);
    S.d = { ix, issues, by, byLevel, st, from: st.from, lay: M.layout(S.doc, ix), errors: M.errorsOf(issues).length, given, iconSet: new Set(S.picks.icons || []) };
  }

  function snapshot() { return JSON.stringify(S.doc); }
  /** One undoable edit: `fn` changes S.doc in place. */
  function edit(fn) {
    const before = snapshot();
    fn(S.doc);
    if (snapshot() === before) return false;
    S.undo.push(before); if (S.undo.length > 120) S.undo.shift();
    S.redo = [];
    after();
    return true;
  }
  function after() {
    for (const n of S.doc.nodes) if (n && n.id) S.used.add(n.id);
    const ids = new Set(S.doc.nodes.map((n) => n.id));
    for (const id of Array.from(S.marked)) if (!ids.has(id)) S.marked.delete(id);
    if (S.sel && !ids.has(S.sel)) S.sel = null;
    if (S.link && !ids.has(S.link)) S.link = null;
    derive();
    if (S.level > S.d.ix.max) { S.level = S.d.ix.max; derive(); }
    later();
  }
  function step(fromStack, toStack) {
    if (!fromStack.length) return;
    toStack.push(snapshot());
    S.doc = JSON.parse(fromStack.pop());
    after();
  }
  const undo = () => step(S.undo, S.redo);
  const redo = () => step(S.redo, S.undo);
  const node = (id) => S.doc.nodes.find((n) => n && n.id === id);
  /** A node's key set or removed, a new key put where the schema lists it (the other keys keep their order). */
  function setKey(n, key, value) {
    if (value === undefined || value === '' || value === null) { delete n[key]; return; }
    if (key in n) { n[key] = value; return; }
    const want = M.NODE_KEYS.indexOf(key);
    const entries = Object.entries(n);
    let at = entries.findIndex(([k]) => M.NODE_KEYS.indexOf(k) > want && want >= 0);
    if (at < 0) at = entries.length;
    entries.splice(at, 0, [key, value]);
    for (const k of Object.keys(n)) delete n[k];
    for (const [k, v] of entries) n[k] = v;
  }
  const setField = (id, key, value) => edit(() => { const n = node(id); if (n) setKey(n, key, value); });

  async function save() {
    if (S.saving || !S.doc) return;
    if (!dirty()) { App.status('Nothing to save'); return; }
    if (S.d.errors) { App.status(`Cannot save the Trail: ${S.d.errors} error${S.d.errors > 1 ? 's' : ''} (see Checks)`, 'bad'); S.open.checks = true; redraw(); return; }
    S.saving = true; redraw();
    App.status('Saving the Trail…', 'busy');
    let r, data;
    try {
      r = await fetch('/api/trail/save', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ json: S.doc, base_mtime: S.mtime }) });
      try { data = await r.json(); } catch (_) { data = { ok: false, error: `HTTP ${r.status}` }; }
    } catch (e) { r = { status: 0 }; data = { ok: false, error: String(e.message || e) }; }
    S.saving = false;
    if (r.status === 409) App.status('trail.json changed on disk since this page read it: Reload (your edits here would be lost; export the CSV first to keep them)', 'bad');
    else if (!data.ok) App.status(`Save of the Trail failed: ${data.error}`, 'bad');
    else { S.base = snapshot(); S.mtime = data.mtime; App.status(data.unchanged ? 'The Trail on disk is already this' : `Saved ${data.file} (${data.nodes} nodes; a backup was kept). ${data.note || ''}`, 'good'); }
    redraw();
  }

  // ------------------------------------------------------------------ small pieces

  let panelEl = null, built = false, R = {}, timer = 0, scrollLeftBottom = false, io = null, pop = null;
  function later() { clearTimeout(timer); timer = setTimeout(redraw, 0); }
  function redraw() { if (panelEl && panelEl.isConnected) render(panelEl); }
  const fmtGold = (x) => Math.round(x).toLocaleString('en-US');
  const cellKey = (...p) => p.join('|');
  const put = (parent, ...kids) => { for (const k of kids) if (k != null && k !== false) parent.append(k); return parent; };

  function inp(key, value, onSet, o) {
    const opt = o || {};
    const e = el('input', { type: opt.type || 'text', class: 'trl-in ' + (opt.cls || ''), value: value == null ? '' : String(value), placeholder: opt.ph || '', title: opt.title || '', style: opt.w ? `width:${opt.w}px` : '', disabled: !!opt.disabled, spellcheck: false });
    if (opt.type === 'number') e.step = opt.step || 'any';
    if (opt.list) e.setAttribute('list', opt.list);
    e.dataset.cell = key; e.dataset.orig = e.value;
    e.addEventListener('change', () => { if (e.value !== e.dataset.orig) onSet(e.value.trim(), e); });
    return e;
  }
  function numIn(key, value, onSet, o) {
    return inp(key, value, (v, e) => {
      if (v === '') { onSet(undefined); return; }
      const x = Number(v.replace(',', '.'));
      if (!Number.isFinite(x)) { e.classList.add('bad'); App.status(`"${v}" is not a number`, 'bad'); return; }
      onSet(x);
    }, Object.assign({ cls: 'n' }, o));
  }
  function sel(key, value, options, onSet, o) {
    const s = el('select', { class: 'trl-in ' + ((o && o.cls) || ''), title: (o && o.title) || '', disabled: !!(o && o.disabled) });
    let hit = false;
    for (const op of options) { const [v, t] = Array.isArray(op) ? op : [op, op]; if (v === value) hit = true; s.appendChild(el('option', { value: v, text: t, selected: v === value })); }
    if (!hit && value != null && value !== '') s.appendChild(el('option', { value, text: `${value} (unknown)`, selected: true }));
    s.dataset.cell = key;
    s.addEventListener('change', () => onSet(s.value));
    return s;
  }
  function btn(text, title, onClick, cls) { return el('button', { type: 'button', class: 'btn small ' + (cls || ''), text, title, onclick: onClick }); }
  function icon(url, px, label) {
    if (url) return el('img', { class: 'trl-ic', src: url, alt: '', width: px, height: px, loading: 'lazy', draggable: false, onerror: (e) => { e.target.replaceWith(icon(null, px, label)); } });
    return el('span', { class: 'trl-ic none', style: `width:${px}px;height:${px}px;font-size:${Math.max(9, Math.round(px * 0.34))}px`, text: String(label || '?').slice(0, 2) });
  }
  const upIcon = (u) => (u && u.icon && S.d.iconSet.has(u.icon) ? `/api/trail/icon/${encodeURIComponent(u.icon)}` : null);

  /** What a node gives, for its tile and its cell: {url, label, name}. */
  function giftOf(n) {
    const g = (n && n.gives) || {};
    const P = S.picks;
    if (g.type === 'upgrade') { const u = S.doc.upgrades[g.upgrade]; return { url: upIcon(u), label: (u && u.name) || g.upgrade || '?', name: u ? u.name || g.upgrade : `${g.upgrade || '?'} (unknown)` }; }
    if (g.type === 'stage') {
      const m = (P.maps || []).find((x) => x.id === g.map);
      const st = m && (m.stages || []).find((x) => x.id === g.stage);
      return { url: st && st.icon, label: 'St', name: st ? `${m.name}: ${st.name}` : `${g.map || '?'}/${g.stage || '?'} (unknown)` };
    }
    const hit = (P[LISTS[g.type]] || []).find((x) => (x && x.id !== undefined ? x.id : x) === g.id);
    const nm = hit ? (hit.name || String(hit.id || hit)) : `${g.id || '?'} (unknown)`;
    return { url: hit && hit.icon, label: M.GIVE_WORDS[g.type] || '?', name: nm };
  }
  function optionsFor(type) {
    const P = S.picks;
    if (type === 'upgrade') return Object.entries(S.doc.upgrades).map(([id, u]) => ({ id, name: (u && u.name) || id, sub: `${(u && u.text) || ''} · ${(u && u.kind) || ''}`, url: upIcon(u) }));
    if (type === 'stage') return [].concat(...(P.maps || []).map((m) => (m.stages || []).map((s) => ({ id: `${m.id}/${s.id}`, name: `${m.name}: ${s.name}`, sub: `${m.id}/${s.id}`, url: s.icon }))));
    return (P[LISTS[type]] || []).map((x) => (typeof x === 'string' ? { id: x, name: x.replace(/^./, (c) => c.toUpperCase()), sub: '' } : { id: x.id, name: x.name || x.id, url: x.icon, sub: [x.id, x.mark, x.evolved ? 'evolution' : '', x.hidden ? 'hidden' : ''].filter(Boolean).join(' · ') }));
  }
  function setWhat(n, type, id) {
    const keep = n.gives && n.gives.type === type ? n.gives : null;
    if (type === 'upgrade') { const g = keep || { type }; g.upgrade = id; if (g.value === undefined && (S.doc.upgrades[id] || {}).kind !== 'word') g.value = (S.doc.upgrades[id] || {}).kind === 'percent' ? 0.03 : 1; n.gives = g; }
    else if (type === 'stage') { const cut = String(id).indexOf('/'); n.gives = { type, map: String(id).slice(0, cut), stage: String(id).slice(cut + 1) }; }
    else n.gives = { type, id };
  }

  /** The pick list under a cell: a filter box and the options with their icons; arrows, Enter, Escape. */
  function closePop() { if (pop) { pop.remove(); pop = null; } }
  function openPick(anchor, options, current, onPick) {
    closePop();
    const box = el('div', { class: 'trl-pop' });
    const q = el('input', { type: 'text', class: 'trl-in', placeholder: 'type to filter…', spellcheck: false });
    const list = el('div', { class: 'trl-pop-list' });
    let shown = [], at = 0;
    const draw = () => {
      const words = q.value.toLowerCase().split(/\s+/).filter(Boolean);
      shown = options.filter((o) => words.every((w) => `${o.id} ${o.name} ${o.sub || ''}`.toLowerCase().includes(w)));
      at = Math.max(0, Math.min(at, shown.length - 1));
      clear(list);
      shown.forEach((o, i) => {
        const taken = o.takenBy ? ` · given by ${o.takenBy}` : '';
        list.appendChild(el('div', { class: 'trl-pop-row' + (i === at ? ' at' : '') + (o.id === current ? ' cur' : ''), onmousedown: (e) => { e.preventDefault(); choose(o); } },
          icon(o.url, 28, o.name), el('span', { class: 'nm', text: o.name }), el('span', { class: 'muted small', text: (o.sub || '') + taken })));
      });
      if (!shown.length) list.appendChild(el('div', { class: 'muted small', text: 'nothing matches' }));
      const cur = list.children[at]; if (cur && cur.scrollIntoView) cur.scrollIntoView({ block: 'nearest' });
    };
    const choose = (o) => { closePop(); anchor.focus(); onPick(o.id); };
    q.addEventListener('input', () => { at = 0; draw(); });
    q.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowDown') { e.preventDefault(); at++; draw(); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); at--; draw(); }
      else if (e.key === 'Enter') { e.preventDefault(); if (shown[at]) choose(shown[at]); }
      else if (e.key === 'Escape' || e.key === 'Tab') { e.preventDefault(); e.stopPropagation(); closePop(); anchor.focus(); }
    });
    q.addEventListener('blur', () => setTimeout(() => { if (pop === box) closePop(); }, 120));
    box.appendChild(q); box.appendChild(list);
    document.body.appendChild(box);
    const r = anchor.getBoundingClientRect();
    box.style.left = `${Math.max(4, Math.min(r.left, window.innerWidth - 330))}px`;
    const below = window.innerHeight - r.bottom > 300;
    box.style[below ? 'top' : 'bottom'] = below ? `${r.bottom + 2}px` : `${window.innerHeight - r.top + 2}px`;
    pop = box; at = Math.max(0, options.findIndex((o) => o.id === current)); draw(); q.focus();
  }

  function modal(title, body, buttons) {
    const back = el('div', { class: 'trl-modal-back' });
    const close = () => back.remove();
    const box = el('div', { class: 'trl-modal' }, el('h3', { text: title }), body,
      el('div', { class: 'trl-modal-btns' }, buttons.map(([text, fn, cls]) => el('button', { type: 'button', class: 'btn ' + (cls || ''), text, onclick: () => { close(); if (fn) fn(); } }))));
    back.appendChild(box);
    back.addEventListener('mousedown', (e) => { if (e.target === back) close(); });
    document.body.appendChild(back);
    return back;
  }

  // ------------------------------------------------------------------ the left pane: the Trail as the game lays it out

  function scale() { return R.view ? Math.max(0.1, R.view.clientWidth / M.W) : 0.5; }
  function drawTrack() {
    const lay = S.d.lay, s = scale();
    R.sizer.style.height = `${Math.round(lay.height * s)}px`;
    R.track.style.height = `${lay.height}px`;
    R.track.style.transform = `scale(${s})`;
    clear(R.motifs); clear(R.rails); clear(R.plates); clear(R.tiles); R.rows = new Map();
    // the motifs, one faint tiled layer per section, and the section plates
    const secs = M.sectionsSorted(S.doc);
    secs.forEach((sec, i) => {
      const lo = Math.max(1, sec.from), hi = secs[i + 1] ? secs[i + 1].from - 1 : Math.max(lay.levels, lo);
      const top = i === secs.length - 1 ? 0 : lay.rowY(hi) - lay.row / 2, bottom = i === 0 ? lay.height : lay.rowY(lo) + lay.row / 2;
      if (MOTIF_SVG[sec.motif] && bottom > top) {
        const tile = `<svg xmlns="http://www.w3.org/2000/svg" width="260" height="260" viewBox="0 0 130 130" fill="white"><g transform="translate(6 8)">${MOTIF_SVG[sec.motif]}</g><g transform="translate(70 72) scale(0.7)">${MOTIF_SVG[sec.motif]}</g></svg>`;
        R.motifs.appendChild(el('div', { class: 'trl-motif', style: `top:${top}px;height:${bottom - top}px;background-image:url("data:image/svg+xml,${encodeURIComponent(tile)}")` }));
      }
      if (sec.from <= lay.levels) R.plates.appendChild(el('div', { class: 'trl-plate', style: `top:${lay.rowY(lo) + lay.row / 2 - 30}px`, text: sec.name || `Section ${i + 1}` }));
    });
    R.plates.appendChild(el('div', { class: 'trl-end', style: `top:${lay.endY - 44}px`, text: (S.doc.end && S.doc.end.text) || '' }));
    // the dark band above the line (rule 6: just above level Trail Level + 1)
    const lineY = lay.rowY(Math.min(lay.levels, S.d.st.level + 1)) - lay.row / 2;
    R.dark.style.height = `${Math.max(0, S.d.st.level >= S.d.ix.max ? 0 : lineY)}px`;
    R.dark.hidden = S.d.st.level >= S.d.ix.max;
    windowRows(); backdrop();
  }
  /** The pane's own gradient: the two colours of the level in the middle of the view, as the game's screen shows them. */
  function backdrop() {
    if (!R.view) return;
    const lay = S.d.lay, s = scale();
    const mid = (R.view.scrollTop + R.view.clientHeight / 2) / s;
    const lv = Math.max(1, Math.min(lay.levels, (lay.rowY(1) - mid) / lay.row + 1));
    const a = M.coloursAt(S.doc, Math.floor(lv)), b = M.coloursAt(S.doc, Math.ceil(lv)), t = lv - Math.floor(lv);
    const mix = (x, y) => `rgb(${x.map((v, i) => Math.round(v + (y[i] - v) * t)).join(',')})`;
    R.view.style.background = `linear-gradient(to bottom, ${mix(a.top, b.top)}, ${mix(a.bottom, b.bottom)})`;
  }
  function windowRows() {
    if (!R.view) return;
    const lay = S.d.lay, s = scale();
    const y0 = R.view.scrollTop / s - lay.row * 2, y1 = (R.view.scrollTop + R.view.clientHeight) / s + lay.row * 2;
    const hi = Math.min(lay.levels, Math.ceil((lay.rowY(1) - y0) / lay.row) + 1), lo = Math.max(1, Math.floor((lay.rowY(1) - y1) / lay.row) + 1);
    for (const [l, g] of R.rows) if (l < lo || l > hi) { g.rail.remove(); g.tile.remove(); R.rows.delete(l); }
    for (let l = lo; l <= hi; l++) if (!R.rows.has(l)) { const g = levelGroup(l); R.rails.appendChild(g.rail); R.tiles.appendChild(g.tile); R.rows.set(l, g); }
  }
  function levelGroup(l) {
    const { ix, lay, st, from, by, byLevel } = S.d;
    const rail = el('div', {}), tile = el('div', {});
    const y = lay.rowY(l);
    const lvIssues = byLevel.get(l) || [];
    tile.appendChild(el('div', { class: 'trl-diamond' + (lvIssues.length ? (lvIssues.some((x) => x.sev === 'error') ? ' err' : ' warn') : '') + (l <= st.level ? ' lit' : ''), style: `left:${lay.diamondX}px;top:${y}px`, title: lvIssues.map((x) => x.text).join('\n') || `level ${l}`, onclick: () => scrollToLevel(l) }, el('span', { text: String(l) })));
    const list = ix.byLevel.get(l) || [];
    for (const n of list) {
      const p = lay.nodes[n.id];
      if (!p || ix.byId.get(n.id) !== n) continue;
      const state = st.state[n.id] || 'locked';
      for (const fid of M.railIds(ix, from, n.id, (x) => st.state[x] === 'closed')) {
        const q = lay.nodes[fid];
        if (!q) continue;
        const dx = p.x - q.x, dy = p.y - q.y, len = Math.hypot(dx, dy), h = n.kind === 'optional' ? 12 : lay.rail;
        const lit = state === 'bought' && st.state[fid] === 'bought';
        rail.appendChild(el('div', { class: 'trl-rail' + (lit ? ' lit' : '') + (state === 'closed' || st.state[fid] === 'closed' ? ' shut' : ''), style: `left:${q.x}px;top:${q.y - h / 2}px;width:${len}px;height:${h}px;transform:rotate(${Math.atan2(dy, dx)}rad)` }));
      }
      const gift = giftOf(n);
      const iss = by.get(n.id) || [];
      const u = n.gives && n.gives.type === 'upgrade' ? S.doc.upgrades[n.gives.upgrade] : null;
      const cap = n.name || (u ? M.fmtValue(u.kind, n.gives.value) || u.name : gift.name);
      const t = el('div', {
        class: `trl-tile ${state} k-${n.kind}` + (n.name ? ' named' : '') + (S.sel === n.id ? ' sel' : '') + (S.marked.has(n.id) ? ' marked' : '') + (S.link === n.id ? ' linking' : ''),
        style: `left:${p.x - p.size / 2}px;top:${p.y - p.size / 2}px;width:${p.size}px;height:${p.size}px`,
        title: `${n.id} · level ${l} · ${M.giveText(S.doc, n, S.picks)} · ${fmtGold(M.priceOf(S.doc, n))} ${S.doc.currency} · ${state}${n.kind === 'choice' ? '\nAlt+click: show this member as the one taken' : ''}${iss.length ? '\n' + iss.map((x) => x.text).join('\n') : ''}`,
        onclick: (e) => tileClick(n, e),
      }, icon(gift.url, Math.round(p.size * 0.74), gift.label),
      iss.length ? el('span', { class: 'trl-badge ' + (iss.some((x) => x.sev === 'error') ? 'err' : 'warn'), text: '!' }) : null,
      state === 'closed' ? el('span', { class: 'trl-strike' }) : null,
      el('span', { class: 'trl-cap' }, el('b', { text: cap }), S.showPrices ? el('i', { text: fmtGold(M.priceOf(S.doc, n)) }) : null));
      tile.appendChild(t);
    }
    // a choice group's bar with its lock marks
    const seen = new Set();
    for (const n of list) {
      if (n.kind !== 'choice' || n.group == null || seen.has(String(n.group))) continue;
      seen.add(String(n.group));
      const xs = list.filter((m) => m.kind === 'choice' && String(m.group) === String(n.group) && lay.nodes[m.id]).map((m) => lay.nodes[m.id].x).sort((a, b) => a - b);
      if (xs.length < 2) continue;
      rail.appendChild(el('div', { class: 'trl-bar-choice', style: `left:${xs[0]}px;top:${y - 9}px;width:${xs[xs.length - 1] - xs[0]}px` }));
      for (let i = 0; i + 1 < xs.length; i++) tile.appendChild(el('div', { class: 'trl-lock', style: `left:${(xs[i] + xs[i + 1]) / 2}px;top:${y}px`, title: `choice ${n.group}: one may be taken` },
        svg('svg', { viewBox: '0 0 16 16', width: 26, height: 26 }, svg('path', { d: 'M4.5 7V5a3.5 3.5 0 0 1 7 0v2h1v7h-9V7zm1.600 0h3.800V5a1.900 1.900 0 0 0-3.800 0z', fill: 'currentColor' }))));
    }
    return { rail, tile };
  }
  function tileClick(n, e) {
    if (S.link && S.link !== n.id) {
      const target = node(S.link);
      edit(() => { const f = Array.isArray(target.from) ? target.from.slice() : []; const i = f.indexOf(n.id); if (i >= 0) f.splice(i, 1); else f.push(n.id); setKey(target, 'from', f.length ? f : undefined); });
      return;
    }
    if (e.altKey && n.kind === 'choice' && n.group != null) { S.choice[M.groupKey(n)] = n.id; derive(); later(); return; }
    select(n.id, 'left');
  }
  function scrollLeftTo(id) {
    const p = S.d.lay.nodes[id];
    if (!p || !R.view) return;
    const y = p.y * scale(), v = R.view;
    if (y < v.scrollTop + 60 || y > v.scrollTop + v.clientHeight - 60) v.scrollTo({ top: Math.max(0, y - v.clientHeight / 2), behavior: 'smooth' });
  }
  function scrollToLevel(l) {
    const b = R.levels && R.levels.querySelector(`.trl-lvl[data-level="${l}"]`);
    if (b) { fill(b); b.scrollIntoView({ block: 'start', behavior: 'smooth' }); }
  }
  function select(id, from) {
    if (S.sel === id && from !== 'left') return;
    S.sel = id;
    for (const t of panelEl.querySelectorAll('.trl-row.sel')) t.classList.remove('sel');
    drawTrack();
    if (from !== 'left') { scrollLeftTo(id); const r = rowEl(id); if (r) r.classList.add('sel'); return; }
    const n = node(id);
    if (!n) return;
    if (!matches(n)) { S.filter = ''; S.onlyIssues = false; drawRight(); }
    const b = R.levels.querySelector(`.trl-lvl[data-level="${n.level}"]`);
    if (b) fill(b);
    const r = rowEl(id);
    if (r) {
      r.classList.add('sel'); r.scrollIntoView({ block: 'center', behavior: 'smooth' });
      // the blocks filled on the way change height: once the scroll has settled, make sure the row is in view
      setTimeout(() => { const again = rowEl(id); if (again && S.sel === id && wantScroll(again)) again.scrollIntoView({ block: 'center' }); }, 650);
    }
  }
  const rowEl = (id) => (R.levels ? R.levels.querySelector(`.trl-row[data-id="${id}"]`) : null);

  // ------------------------------------------------------------------ the right pane: the blocks above the levels

  function fold(key, title, summary, build) {
    const d = el('details', { class: 'trl-fold', open: !!S.open[key] });
    d.appendChild(el('summary', {}, el('b', { text: title }), el('span', { class: 'muted small', text: summary || '' })));
    const body = el('div', { class: 'trl-fold-body' });
    d.appendChild(body);
    if (S.open[key]) build(body);
    d.addEventListener('toggle', () => { S.open[key] = d.open; store('open', JSON.stringify(S.open)); if (d.open && !body.firstChild) build(body); });
    return d;
  }
  const lab = (text, ...kids) => el('label', { class: 'trl-lab' }, el('span', { text }), kids);

  function priceBlock(body) {
    const p = S.doc.price, tot = M.totals(S.doc, S.perRun);
    const set = (k) => (v) => { if (v !== undefined) edit((d) => { d.price[k] = v; }); };
    body.appendChild(el('div', { class: 'trl-line' },
      lab('base', numIn('price|base', p.base, set('base'), { w: 70 })), lab('k', numIn('price|k', p.k, set('k'), { w: 70 })),
      lab('power', numIn('price|power', p.power, set('power'), { w: 70 })), lab('round to', numIn('price|round', p.round, set('round'), { w: 70 })),
      el('span', { class: 'muted small', text: 'a node costs round(base + k × level ^ power) × its multiplier, unless it has its own price' })));
    body.appendChild(el('div', { class: 'trl-line' },
      lab('coins a run', numIn('page|perrun', S.perRun, (v) => { if (v > 0) { S.perRun = v; store('perrun', String(v)); later(); } }, { w: 80, title: 'a page setting for the "runs" below, never written to the file' })),
      el('span', { text: `All ${tot.nodes} nodes: ${fmtGold(tot.all)} ${S.doc.currency}.` }),
      el('span', { text: `Every required node (a choice once, at its dearest): ${fmtGold(tot.required)}, about ${tot.runs == null ? '?' : Math.ceil(tot.runs)} runs.` }),
      el('span', { class: 'muted', text: `Optional nodes: ${fmtGold(tot.optional)} more (about ${tot.runs_with_optional == null ? '?' : Math.ceil(tot.runs_with_optional)} runs for everything a player can buy).` })));
    body.appendChild(priceChart(tot));
  }
  /** One series (what a level's node costs on the curve) with a crosshair readout; nodes off the curve as rings. */
  function priceChart(tot) {
    const Wd = 560, Hd = 150, L = 46, Rr = 10, T = 8, B = 22;
    const maxL = Math.max(10, S.d.ix.max);
    const off = S.d.ix.nodes.filter((n) => n.level >= 1 && M.priceOf(S.doc, n) !== M.curvePrice(S.doc.price, n.level));
    const maxP = Math.max(10, M.curvePrice(S.doc.price, maxL), ...off.map((n) => M.priceOf(S.doc, n)));
    const X = (l) => L + (Wd - L - Rr) * (l - 1) / (maxL - 1), Y = (v) => T + (Hd - T - B) * (1 - v / maxP);
    const g = svg('svg', { class: 'trl-chart', viewBox: `0 0 ${Wd} ${Hd}`, role: 'img', 'aria-label': 'the price of a node by level' });
    for (const f of [0, 0.5, 1]) {
      g.appendChild(svg('line', { x1: L, x2: Wd - Rr, y1: Y(maxP * f), y2: Y(maxP * f), class: 'grid' }));
      g.appendChild(svg('text', { x: L - 6, y: Y(maxP * f) + 4, 'text-anchor': 'end', class: 'tick' }, fmtGold(maxP * f)));
    }
    for (const l of Array.from(new Set([1, Math.round(maxL / 4), Math.round(maxL / 2), Math.round(maxL * 3 / 4), maxL]))) if (l >= 1) g.appendChild(svg('text', { x: X(l), y: Hd - 6, 'text-anchor': 'middle', class: 'tick' }, String(l)));
    let path = '';
    for (let l = 1; l <= maxL; l++) path += `${l === 1 ? 'M' : 'L'}${X(l).toFixed(1)} ${Y(M.curvePrice(S.doc.price, l)).toFixed(1)}`;
    g.appendChild(svg('path', { d: path, class: 'line' }));
    for (const n of off) g.appendChild(svg('circle', { cx: X(n.level), cy: Y(M.priceOf(S.doc, n)), r: 4, class: 'dot' }));
    const cross = svg('line', { y1: T, y2: Hd - B, class: 'cross', visibility: 'hidden' });
    g.appendChild(cross);
    const read = el('div', { class: 'trl-read muted small', text: 'Hover the chart: the price at a level, its nodes, the gold to there. Rings are nodes off the curve (an own price or a multiplier).' });
    const hit = svg('rect', { x: L, y: T, width: Wd - L - Rr, height: Hd - T - B, fill: 'transparent' });
    hit.addEventListener('mousemove', (e) => {
      const r = g.getBoundingClientRect();
      const l = Math.max(1, Math.min(maxL, Math.round(1 + ((e.clientX - r.left) / r.width * Wd - L) / (Wd - L - Rr) * (maxL - 1))));
      cross.setAttribute('x1', X(l)); cross.setAttribute('x2', X(l)); cross.setAttribute('visibility', 'visible');
      const nodes = (S.d.ix.byLevel.get(l) || []).map((n) => `${n.id} ${fmtGold(M.priceOf(S.doc, n))}`).join(', ');
      const t = tot.levels[l - 1];
      read.textContent = `Level ${l}: the curve gives ${fmtGold(M.curvePrice(S.doc.price, l))}${nodes ? ` · ${nodes}` : ' · no node yet'}${t ? ` · required gold to here ${fmtGold(t.cumulative)}${t.runs != null ? `, about ${Math.ceil(t.runs)} runs` : ''}` : ''}`;
    });
    hit.addEventListener('mouseleave', () => cross.setAttribute('visibility', 'hidden'));
    g.appendChild(hit);
    return el('div', { class: 'trl-chart-box' }, el('div', { class: 'muted small', text: `Price of a node by level (${S.doc.currency})` }), g, read);
  }

  function totalsBlock(body) {
    const grid = el('div', { class: 'trl-totals' });
    for (const r of M.upgradeTotals(S.doc)) {
      const u = S.doc.upgrades[r.type];
      const parts = [r.sure ? `sure ${M.fmtValue(r.kind, r.sure)}` : '', r.optional ? `optional ${M.fmtValue(r.kind, r.optional)}` : '', r.choice ? `choices up to ${M.fmtValue(r.kind, r.choice)}` : ''].filter(Boolean).join(', ');
      grid.appendChild(el('div', { class: 'trl-total' + (r.count ? '' : ' none'), title: `${r.name} (${r.type})${parts ? ': ' + parts : ''}` }, icon(upIcon(u), 26, r.name), el('span', { text: r.line })));
    }
    body.appendChild(grid);
    const stats = M.statTotals(S.doc);
    if (stats.length) body.appendChild(el('p', { class: 'muted small', text: 'By stat, everything bought: ' + stats.map((s) => `${s.stat} ${s.op} ${s.total > 0 ? '+' : ''}${s.total}`).join(' · ') }));
  }

  function sectionsBlock(body) {
    const t = el('div', { class: 'trl-table' });
    S.doc.sections.forEach((sec, i) => {
      const colour = (k) => { const c = el('input', { type: 'color', class: 'trl-col', value: '#' + (/^[0-9a-f]{6}$/i.test(sec[k] || '') ? sec[k] : '888888'), title: `${k} colour` }); c.dataset.cell = cellKey('sec', i, k + 'c'); c.addEventListener('change', () => edit((d) => { d.sections[i][k] = c.value.slice(1).toLowerCase(); })); return c; };
      t.appendChild(el('div', { class: 'trl-line' },
        lab('from level', numIn(cellKey('sec', i, 'from'), sec.from, (v) => { if (v >= 1) edit((d) => { d.sections[i].from = Math.round(v); d.sections.sort((a, b) => a.from - b.from); }); }, { w: 60 })),
        lab('name', inp(cellKey('sec', i, 'name'), sec.name, (v) => edit((d) => { d.sections[i].name = v; }), { w: 170 })),
        lab('top', colour('top'), inp(cellKey('sec', i, 'top'), sec.top, (v) => edit((d) => { d.sections[i].top = v.replace(/^#/, '').toLowerCase(); }), { w: 70, cls: 'mono' })),
        lab('bottom', colour('bottom'), inp(cellKey('sec', i, 'bottom'), sec.bottom, (v) => edit((d) => { d.sections[i].bottom = v.replace(/^#/, '').toLowerCase(); }), { w: 70, cls: 'mono' })),
        lab('motif', sel(cellKey('sec', i, 'motif'), sec.motif || 'none', M.MOTIFS, (v) => edit((d) => { d.sections[i].motif = v; }))),
        btn('✕', 'remove this section', () => edit((d) => { d.sections.splice(i, 1); }), 'ghost')));
    });
    body.appendChild(t);
    body.appendChild(el('div', { class: 'trl-line' },
      btn('+ section', 'a new section starting 15 levels above the last one', () => edit((d) => { const last = d.sections[d.sections.length - 1]; d.sections.push({ from: last ? last.from + 15 : 1, name: 'New section', top: last ? last.top : 'f7b24a', bottom: last ? last.bottom : 'ef7d22', motif: 'none' }); })),
      lab('the end plate', inp('end|text', S.doc.end.text, (v) => edit((d) => { d.end.text = v; }), { w: 220 })),
      el('span', { class: 'muted small', text: 'The backdrop blends into a section over the three levels before it starts.' })));
  }

  function upgradesBlock(body) {
    const count = new Map();
    for (const n of S.d.ix.nodes) if (n.gives && n.gives.type === 'upgrade') count.set(n.gives.upgrade, (count.get(n.gives.upgrade) || 0) + 1);
    const icons = (S.picks.icons || []).slice();
    for (const [t, u] of Object.entries(S.doc.upgrades)) {
      const used = count.get(t) || 0;
      const up = (fn) => edit((d) => fn(d.upgrades[t]));
      const fx = el('div', { class: 'trl-fx' });
      (u.effects || []).forEach((e, ei) => fx.appendChild(el('span', { class: 'trl-fx-row' },
        inp(cellKey('up', t, 'fx', ei, 'stat'), e.stat, (v) => up((x) => { x.effects[ei].stat = v; }), { w: 130, list: 'trl-stats', title: 'the player stat' }),
        sel(cellKey('up', t, 'fx', ei, 'op'), e.op, ['add', 'mul'], (v) => up((x) => { x.effects[ei].op = v; })),
        numIn(cellKey('up', t, 'fx', ei, 'per'), e.per, (v) => { if (v !== undefined) up((x) => { x.effects[ei].per = v; }); }, { w: 52, title: 'per: the stat gets the node’s value × this' }),
        btn('✕', 'remove this effect', () => up((x) => { x.effects.splice(ei, 1); }), 'ghost'))));
      fx.appendChild(btn('+ effect', 'one more stat this type changes', () => up((x) => { if (!Array.isArray(x.effects)) x.effects = []; x.effects.push({ stat: 'might', op: 'mul', per: 1.0 }); }), 'ghost'));
      body.appendChild(el('div', { class: 'trl-up' + ((S.d.issues.some((x) => x.upgrade === t)) ? ' flagged' : ''), title: S.d.issues.filter((x) => x.upgrade === t).map((x) => x.text).join('\n') },
        icon(upIcon(u), 36, u.name || t),
        el('div', { class: 'trl-up-main' },
          el('div', { class: 'trl-line' },
            el('code', { text: t, title: 'the type’s id (nodes name it)' }), el('span', { class: 'muted small', text: `${used} node${used === 1 ? '' : 's'}` }),
            lab('name', inp(cellKey('up', t, 'name'), u.name, (v) => up((x) => { x.name = v; }), { w: 130 })),
            lab('icon', sel(cellKey('up', t, 'icon'), u.icon || '', [['', '(none)']].concat(icons.map((i) => [i, i])), (v) => up((x) => { x.icon = v; }))),
            lab('written as', sel(cellKey('up', t, 'kind'), u.kind, M.VALUE_KINDS, (v) => up((x) => { x.kind = v; }), { title: 'percent: 0.03 reads +3% · flat: +2 · count: +1 · seconds: +2 s · word: no amount' })),
            lab('text', inp(cellKey('up', t, 'text'), u.text, (v) => up((x) => { x.text = v; }), { w: 230 })),
            btn('✕', used ? `${used} node${used === 1 ? ' gives' : 's give'} this type: change or delete them first` : 'remove this upgrade type', () => { if (!used) edit((d) => { delete d.upgrades[t]; }); }, 'ghost' + (used ? ' off' : ''))),
          el('div', { class: 'trl-line' }, el('span', { class: 'muted small', text: 'effects' }), fx,
            lab('warning before buying', inp(cellKey('up', t, 'warn'), u.warn, (v) => up((x) => { if (v) x.warn = v; else delete x.warn; }), { w: 300 }))))));
    }
    const name = el('input', { type: 'text', class: 'trl-in', placeholder: 'new type id (a_z, 0-9, _)', style: 'width:180px' });
    body.appendChild(el('div', { class: 'trl-line' }, name, btn('+ upgrade type', 'a new type of permanent upgrade', () => {
      const id = name.value.trim();
      if (!/^[a-z0-9_]+$/.test(id) || S.doc.upgrades[id]) { App.status(id ? `"${id}" is taken or not a plain id` : 'Type the new type’s id first', 'bad'); return; }
      edit((d) => { d.upgrades[id] = { name: id.replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase()), icon: (S.picks.icons || []).includes(id) ? id : '', kind: 'percent', text: '', effects: [{ stat: 'might', op: 'mul', per: 1.0 }] }; });
    })));
  }

  function checksBlock(body) {
    const list = S.d.issues.slice().sort((a, b) => (a.sev === 'error' ? 0 : 1) - (b.sev === 'error' ? 0 : 1) || (a.level || 0) - (b.level || 0));
    if (!list.length) { body.appendChild(el('p', { class: 'good-text', text: 'No issues: the Trail can be saved and played.' })); return; }
    for (const x of list.slice(0, 300)) {
      body.appendChild(el('div', { class: 'trl-issue ' + x.sev, onclick: () => { if (x.id && node(x.id)) select(x.id, 'left'), scrollLeftTo(x.id); else if (x.level) scrollToLevel(x.level); else if (x.upgrade) { S.open.upgrades = true; redraw(); } else if (x.section != null) { S.open.sections = true; redraw(); } } },
        el('span', { class: 'achip ' + (x.sev === 'error' ? 'bad' : 'warn'), text: x.sev === 'error' ? 'error' : 'warning' }), el('span', { text: x.text })));
    }
    if (list.length > 300) body.appendChild(el('p', { class: 'muted small', text: `and ${list.length - 300} more` }));
  }

  // ------------------------------------------------------------------ the right pane: levels and rows

  function matches(n) {
    if (S.onlyIssues && !S.d.by.has(n.id)) return false;
    const q = S.filter.trim().toLowerCase();
    if (!q) return true;
    const g = n.gives || {};
    const hay = `${n.id} ${n.kind} ${g.type} ${M.giveWhat(g)} ${giftOf(n).name} ${n.group || ''} ${n.name || ''} ${n.note || ''} ${(n.from || []).join(' ')}`.toLowerCase();
    return q.split(/\s+/).every((w) => {
      const m = /^(\d+)(?:-(\d+))?$/.exec(w);
      if (m) return n.level >= Number(m[1]) && n.level <= Number(m[2] || m[1]);
      return hay.includes(w);
    });
  }

  function toolsBar() {
    const bar = el('div', { class: 'trl-tools' });
    const f = el('input', { type: 'search', class: 'trl-in', placeholder: 'filter: might, choice, outlaw, n042, 10-25 …', value: S.filter, style: 'width:260px', title: 'words match the id, kind, what it gives, group, name and note; a number or a range (10-25) matches levels' });
    f.dataset.cell = 'tools|filter';
    f.addEventListener('input', () => { S.filter = f.value; clearTimeout(timer); timer = setTimeout(() => { drawRight(); const again = R.right.querySelector('[data-cell="tools|filter"]'); if (again) { again.focus(); try { again.setSelectionRange(again.value.length, again.value.length); } catch (_) { /* a search box some browsers will not let us place the caret in */ } } }, 180); });
    const { ix } = S.d;
    const many = el('input', { type: 'number', class: 'trl-in n', value: '5', min: 1, max: 100, style: 'width:52px', title: 'how many levels to add' });
    bar.appendChild(el('div', { class: 'trl-line' }, f,
      el('label', { class: 'trl-check' }, el('input', { type: 'checkbox', checked: S.onlyIssues, onchange: (e) => { S.onlyIssues = e.target.checked; drawRight(); } }), 'only rows with issues'),
      btn(S.order === 'high' ? 'Highest level first' : 'Lowest level first', 'switch the order of the levels below', () => { S.order = S.order === 'high' ? 'low' : 'high'; store('order', S.order); drawRight(); }),
      el('span', { class: 'spacer' }),
      btn('+', 'add this many levels on top of the Trail, each with one plain node (then pick what each gives)', () => { const k = Math.max(1, Math.min(100, Math.round(Number(many.value) || 1))); edit((d) => { let top = M.index(d).max; for (let i = 0; i < k; i++) M.addNode(d, ++top, null, S.used); }); }), many,
      el('span', { class: 'muted small', text: `levels on top · ${ix.nodes.length} nodes on ${ix.max} levels` })));
    if (S.marked.size) {
      const field = el('select', { class: 'trl-in' });
      for (const [v, t] of [['value', 'value'], ['upgrade', 'upgrade type'], ['kind', 'kind'], ['price', 'own price'], ['price_mult', 'price multiplier'], ['level', 'level'], ['group', 'group'], ['need', 'need (all / any)'], ['x', 'x'], ['name', 'name'], ['note', 'note']]) field.appendChild(el('option', { value: v, text: t }));
      const val = el('input', { type: 'text', class: 'trl-in', placeholder: 'value (empty clears it)', style: 'width:150px' });
      const ids = () => Array.from(S.marked);
      bar.appendChild(el('div', { class: 'trl-line trl-bulk' }, el('b', { text: `${S.marked.size} selected` }), 'set', field, 'to', val,
        btn('Set', 'set the field on every selected node (one undo step)', () => bulkSet(field.value, val.value.trim()), 'primary'),
        btn('▲ level', 'move the selected nodes one level up', () => edit((d) => { for (const id of ids()) M.moveNode(d, id, 1); })),
        btn('▼ level', 'move the selected nodes one level down', () => edit((d) => { for (const id of ids()) M.moveNode(d, id, -1); })),
        btn('Duplicate', 'a copy of each selected node, beside it', () => edit((d) => { for (const id of ids()) M.duplicateNode(d, id, S.used); })),
        btn('Delete', 'delete the selected nodes', () => edit((d) => { M.deleteNodes(d, ids()); }), 'danger'),
        btn('Clear selection', '', () => { S.marked.clear(); later(); }, 'ghost')));
    }
    return bar;
  }
  function bulkSet(field, text) {
    let bad = '';
    edit((d) => {
      for (const id of S.marked) {
        const n = d.nodes.find((x) => x.id === id);
        if (!n) continue;
        if (field === 'value' || field === 'upgrade') {
          if (!n.gives || n.gives.type !== 'upgrade') { if (field === 'upgrade' && d.upgrades[text]) setWhat(n, 'upgrade', text); continue; }
          if (field === 'upgrade') { if (d.upgrades[text]) n.gives.upgrade = text; else bad = `no upgrade type "${text}"`; continue; }
          const v = M.parseValue((d.upgrades[n.gives.upgrade] || {}).kind, text);
          if (v === null) bad = `"${text}" is not an amount`; else if (v === undefined) delete n.gives.value; else n.gives.value = v;
        } else if (['price', 'price_mult', 'x', 'level'].includes(field)) {
          const v = text === '' ? undefined : Number(text.replace(',', '.'));
          if (v !== undefined && !Number.isFinite(v)) { bad = `"${text}" is not a number`; continue; }
          if (field === 'level') { if (v >= 1) n.level = Math.round(v); } else setKey(n, field, v);
        } else if (field === 'kind') { if (M.KINDS.includes(text)) setKind(d, n, text); else bad = 'kind is node, choice or optional'; }
        else setKey(n, field, text);
      }
      M.sortNodes(d);
    });
    if (bad) App.status(bad, 'bad');
  }
  function setKind(d, n, kind) {
    n.kind = kind;
    if (kind !== 'choice') { delete n.group; return; }
    if (n.group) return;
    const mate = d.nodes.find((m) => m !== n && m.level === n.level && m.kind === 'choice' && m.group);
    let g = mate ? mate.group : `c${n.level}`;
    if (!mate) for (let k = 0; d.nodes.some((m) => m.group === g); k++) g = `c${n.level}${String.fromCharCode(97 + k)}`;
    setKey(n, 'group', g);
  }

  function drawRight() {
    const keep = R.right.scrollTop;
    const was = new Set(Array.from(R.levels.children).filter((b) => b._full).map((b) => b.dataset.level));
    clear(R.top); clear(R.levels);
    const { ix, issues, errors } = S.d;
    R.top.appendChild(fold('price', 'Prices', `${S.doc.price.base} + ${S.doc.price.k} × level ^ ${S.doc.price.power}, rounded to ${S.doc.price.round}`, priceBlock));
    R.top.appendChild(fold('totals', 'What it adds up to', 'every upgrade type over all its nodes', totalsBlock));
    R.top.appendChild(fold('sections', 'Sections and the end plate', `${S.doc.sections.length} backdrops: ${S.doc.sections.map((s) => `${s.name} from ${s.from}`).join(', ')}`, sectionsBlock));
    R.top.appendChild(fold('upgrades', 'Upgrade types', `${Object.keys(S.doc.upgrades).length} types a node can give`, upgradesBlock));
    R.top.appendChild(fold('checks', 'Checks', issues.length ? `${errors} error${errors === 1 ? '' : 's'} (they block Save), ${issues.length - errors} warning${issues.length - errors === 1 ? '' : 's'}` : 'no issues', checksBlock));
    clear(R.tools).appendChild(toolsBar());
    const stats = el('datalist', { id: 'trl-stats' }); for (const s of S.picks.stats || []) stats.appendChild(el('option', { value: s }));
    const idl = el('datalist', { id: 'trl-ids' }); for (const n of ix.nodes) idl.appendChild(el('option', { value: n.id }));
    R.top.appendChild(stats); R.top.appendChild(idl);
    if (io) io.disconnect();
    io = new IntersectionObserver((list) => { for (const e of list) { if (e.isIntersecting) fill(e.target); else empty(e.target); } }, { root: R.right, rootMargin: '900px 0px' });
    const filtering = !!S.filter.trim() || S.onlyIssues;
    const levels = [];
    for (let l = 1; l <= Math.max(1, ix.max); l++) levels.push(l);
    if (S.order === 'high') levels.reverse();
    let shown = 0;
    for (const l of levels) {
      const rows = (ix.byLevel.get(l) || []).filter(matches);
      if (filtering && !rows.length) continue;
      shown += rows.length;
      const b = el('div', { class: 'trl-lvl', dataset: { level: String(l) }, style: `min-height:${30 + rows.length * S.rowH}px` });
      b._rows = rows;
      R.levels.appendChild(b);
      if (was.has(String(l))) fill(b);
      io.observe(b);
    }
    if (filtering) R.levels.insertBefore(el('p', { class: 'muted small', text: `${shown} of ${ix.nodes.length} nodes match` }), R.levels.firstChild);
    if (!ix.nodes.length) R.levels.appendChild(el('p', { class: 'muted', text: 'The Trail has no node yet: "+ node" on level 1 starts it, or import a CSV.' }));
    R.right.scrollTop = keep;
  }
  function empty(b) {
    if (!b._full || b.contains(document.activeElement) || b.querySelector('.trl-row.sel')) return;
    b.style.minHeight = `${b.offsetHeight}px`;
    clear(b); b._full = false;
  }
  function fill(b) {
    if (b._full) return;
    b._full = true; b.style.minHeight = '';
    const l = Number(b.dataset.level);
    const { ix, byLevel } = S.d;
    const all = ix.byLevel.get(l) || [];
    const sec = M.sectionAt(S.doc, l).cur, col = M.coloursAt(S.doc, l);
    const li = byLevel.get(l) || [];
    b.appendChild(el('div', { class: 'trl-lvl-head' + (li.length ? ' flagged' : '') },
      el('span', { class: 'trl-lv', text: String(l), style: `background:linear-gradient(rgb(${col.top.join(',')}), rgb(${col.bottom.join(',')}))`, title: sec ? `section ${sec.name}` : 'no section' }),
      el('span', { class: 'muted small', text: `${all.length} node${all.length === 1 ? '' : 's'} · curve ${fmtGold(M.curvePrice(S.doc.price, l))}${sec && sec.from === l ? ` · ${sec.name} begins` : ''}` }),
      li.length ? el('span', { class: 'trl-flag ' + (li.some((x) => x.sev === 'error') ? 'err' : 'warn'), text: li.map((x) => x.text).join(' · ') }) : null,
      el('span', { class: 'spacer' }),
      btn('+ node', 'one more node on this level, like its last one (a choice joins the group)', () => edit((d) => {
        const last = all[all.length - 1];
        const id = M.addNode(d, l, last, S.used);
        const n = d.nodes.find((x) => x.id === id);
        if (last && last.kind === 'choice') { n.kind = 'choice'; setKey(n, 'group', last.group); }
        S.sel = id;
      })),
      btn('+ level above', `a new level ${l + 1}; the levels above move one up`, () => edit((d) => { S.sel = M.insertLevel(d, l + 1, S.used); })),
      btn('+ level below', `a new level ${l}; this level and the ones above move one up`, () => edit((d) => { S.sel = M.insertLevel(d, l, S.used); })),
      btn('✕ level', 'remove this level and its nodes; the levels above move one down (Ctrl+Z brings it back)', () => edit((d) => { M.removeLevel(d, l); }), 'ghost')));
    const host = el('div', { class: 'trl-rows' });
    for (const n of b._rows) host.appendChild(rowOf(n));
    b.appendChild(host);
    const first = host.firstChild;
    if (first && first.offsetHeight > 10 && Math.abs(first.offsetHeight + 3 - S.rowH) > 2) S.rowH = first.offsetHeight + 3;
  }

  function rowOf(n) {
    const id = n.id, g = n.gives || {}, iss = S.d.by.get(id) || [];
    const u = g.type === 'upgrade' ? S.doc.upgrades[g.upgrade] : null;
    const gift = giftOf(n);
    const curve = Math.round(M.curvePrice(S.doc.price, n.level || 1) * (typeof n.price_mult === 'number' ? n.price_mult : 1));
    const row = el('div', { class: 'trl-row' + (S.sel === id ? ' sel' : '') + (iss.length ? (iss.some((x) => x.sev === 'error') ? ' err' : ' warn') : '') + ` k-${n.kind}`, dataset: { id } });
    const ck = el('input', { type: 'checkbox', checked: S.marked.has(id), title: 'select (Shift+click: every row from the last one selected to here)' });
    ck.addEventListener('click', (e) => {
      const order = Array.from(R.levels.querySelectorAll('.trl-lvl')).reduce((a, b) => a.concat(b._rows.map((x) => x.id)), []);
      if (e.shiftKey && S.lastMark && order.includes(S.lastMark)) { const [a, b] = [order.indexOf(S.lastMark), order.indexOf(id)].sort((x, y) => x - y); for (const k of order.slice(a, b + 1)) S.marked.add(k); }
      else if (ck.checked) S.marked.add(id); else S.marked.delete(id);
      S.lastMark = id; later();
    });
    const what = el('button', { type: 'button', class: 'trl-what', title: `${gift.name}: click or press Enter to pick from the list` }, icon(gift.url, 22, gift.label), el('span', { text: gift.name }));
    what.dataset.cell = cellKey(id, 'what');
    what.addEventListener('click', () => {
      const opts = optionsFor(g.type);
      for (const o of opts) { const by = g.type !== 'upgrade' && S.d.given.get(g.type + ':' + o.id); if (by && by !== id) o.takenBy = by; }
      openPick(what, opts, M.giveWhat(g), (v) => edit(() => setWhat(node(id), g.type, v)));
    });
    const valueCell = g.type === 'upgrade'
      ? inp(cellKey(id, 'value'), u ? M.fmtValue(u.kind, g.value) : (g.value == null ? '' : g.value), (v, e) => {
        const x = M.parseValue(u ? u.kind : 'flat', v);
        if (x === null) { e.classList.add('bad'); App.status(`"${v}" is not an amount (type 3 or +3% for three percent)`, 'bad'); return; }
        edit(() => { const m = node(id); if (x === undefined) delete m.gives.value; else m.gives.value = x; });
      }, { w: 62, cls: 'n', title: u && u.kind === 'percent' ? 'as the player reads it: type 3 for +3%' : 'the amount', disabled: !!(u && u.kind === 'word') })
      : el('span', { class: 'trl-in ghostcell', style: 'width:62px' });
    const f = S.d.from[id] || { ids: [], rails: [], auto: true, terms: [] };
    const chips = el('span', { class: 'trl-from', title: f.auto ? `auto: it hangs on the level below (rails from ${f.rails.join(', ') || 'nothing: the first level'}); it opens when that level is done` : 'the nodes this one connects from: it needs them bought (all, or any one)' });
    if (f.auto) chips.appendChild(el('span', { class: 'achip', text: f.rails.length ? `auto: ${f.rails.join(' ')}` : 'auto' }));
    else for (const fid of (Array.isArray(n.from) ? n.from : [])) chips.appendChild(el('span', { class: 'achip from' + (S.d.ix.byId.has(fid) ? '' : ' bad') }, fid, el('button', { type: 'button', tabindex: -1, text: '×', title: `stop connecting from ${fid}`, onclick: () => edit(() => { const m = node(id); const left = m.from.filter((x) => x !== fid); setKey(m, 'from', left.length ? left : undefined); }) })));
    const addFrom = inp(cellKey(id, 'from'), '', (v) => edit(() => { const m = node(id); const cur = Array.isArray(m.from) ? m.from.slice() : []; for (const x of v.split(/[\s,;]+/).filter(Boolean)) if (!cur.includes(x)) cur.push(x); setKey(m, 'from', cur.length ? cur : undefined); }), { w: 58, ph: '+id', list: 'trl-ids', title: 'type a node id (or several) and press Enter; empty list = auto' });
    put(row, ck,
      inp(cellKey(id, 'id'), id, (v, e) => { if (!edit((d) => { M.renameId(d, id, v); })) { e.value = id; App.status(`"${v}" is taken or not a plain id`, 'bad'); } else { if (S.sel === id) S.sel = v; } }, { w: 56, cls: 'mono id', title: 'the id (saves hold it: rename only a node no build has shipped)' }),
      sel(cellKey(id, 'kind'), n.kind, [['node', 'plain'], ['choice', 'choice'], ['optional', 'optional']], (v) => edit((d) => setKind(d, node(id), v)), { cls: 'kind' }),
      sel(cellKey(id, 'type'), g.type, M.GIVES.map((t) => [t, M.GIVE_WORDS[t]]), (v) => edit(() => { const first = optionsFor(v)[0]; setWhat(node(id), v, first ? first.id : ''); }), { cls: 'type' }),
      what, valueCell,
      numIn(cellKey(id, 'price'), n.price, (v) => setField(id, 'price', v), { w: 66, ph: fmtGold(curve), title: `own price (empty = the curve: ${fmtGold(curve)})` }),
      numIn(cellKey(id, 'mult'), n.price_mult, (v) => setField(id, 'price_mult', v === 1 ? undefined : v), { w: 44, ph: '×1', title: 'price multiplier on the curve', disabled: typeof n.price === 'number' }),
      chips, addFrom,
      el('button', { type: 'button', tabindex: -1, class: 'btn small ghost' + (S.link === id ? ' on' : ''), text: '⌖', title: 'connect by clicking: then click the nodes on the left this one connects from (Esc ends)', onclick: () => { S.link = S.link === id ? null : id; S.sel = id; later(); } }),
      sel(cellKey(id, 'need'), n.need || 'all', [['all', 'all'], ['any', 'any']], (v) => setField(id, 'need', v === 'all' ? undefined : v), { cls: 'need', title: 'needs all of the nodes it connects from, or any one' }),
      inp(cellKey(id, 'group'), n.group, (v) => setField(id, 'group', v), { w: 50, ph: 'group', disabled: n.kind !== 'choice', title: 'choice group: members on this level share it (2 to 4), one may be taken' }),
      numIn(cellKey(id, 'x'), n.x, (v) => setField(id, 'x', v), { w: 46, ph: 'x', title: 'place across the screen, 0 to 1 (empty = spread by the rule; above 0.75 is kept free)' }),
      inp(cellKey(id, 'name'), n.name, (v) => setField(id, 'name', v), { cls: 'grow', ph: 'name', title: 'a milestone’s own name (the player reads it)' }),
      inp(cellKey(id, 'note'), n.note, (v) => setField(id, 'note', v), { cls: 'grow', ph: 'note', title: 'a designer’s note the game never shows' }),
      el('span', { class: 'trl-acts' },
        el('button', { type: 'button', tabindex: -1, class: 'btn small ghost', text: '▲', title: 'one level up (Alt+Up)', onclick: () => edit((d) => { M.moveNode(d, id, 1); }) }),
        el('button', { type: 'button', tabindex: -1, class: 'btn small ghost', text: '▼', title: 'one level down (Alt+Down)', onclick: () => edit((d) => { M.moveNode(d, id, -1); }) }),
        el('button', { type: 'button', tabindex: -1, class: 'btn small ghost', text: '⧉', title: 'duplicate (Ctrl+D)', onclick: () => edit((d) => { S.sel = M.duplicateNode(d, id, S.used); }) }),
        el('button', { type: 'button', tabindex: -1, class: 'btn small ghost', text: '✕', title: 'delete (Ctrl+Delete)', onclick: () => edit((d) => { M.deleteNodes(d, [id]); }) })));
    if (iss.length) row.appendChild(el('div', { class: 'trl-row-iss', text: iss.map((x) => x.text).join(' · ') }));
    row.addEventListener('focusin', () => select(id, 'right'));
    row.addEventListener('keydown', (e) => rowKey(e, id));
    return row;
  }
  function rowKey(e, id) {
    const t = e.target;
    const field = (t.dataset && t.dataset.cell || '').split('|')[1];
    if (e.key === 'Enter' && field && t.tagName === 'INPUT') {
      e.preventDefault();
      const rows = Array.from(R.levels.querySelectorAll('.trl-row'));
      const next = rows[rows.findIndex((r) => r.dataset.id === id) + (e.shiftKey ? -1 : 1)];
      const target = next && next.querySelector(`[data-cell="${cellKey(next.dataset.id, field)}"]`);
      if (target && !target.disabled) { target.focus(); if (target.select) target.select(); } else t.blur();
      return;
    }
    if (e.altKey && (e.key === 'ArrowUp' || e.key === 'ArrowDown')) { e.preventDefault(); t.blur(); edit((d) => { M.moveNode(d, id, e.key === 'ArrowUp' ? 1 : -1); }); focusLater(cellKey(id, field || 'what')); return; }
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'd') { e.preventDefault(); t.blur(); let nid = null; edit((d) => { nid = M.duplicateNode(d, id, S.used); }); if (nid) focusLater(cellKey(nid, field || 'what')); return; }
    if ((e.ctrlKey || e.metaKey) && e.key === 'Delete') { e.preventDefault(); t.blur(); edit((d) => { M.deleteNodes(d, [id]); }); }
  }
  let wantFocus = null;
  function focusLater(key) { wantFocus = key; }

  // ------------------------------------------------------------------ CSV, JSON

  function exportCsv() { U.download('trail.csv', M.toCsv(S.doc)); App.status('Exported trail.csv (your browser’s downloads): one row per node; the last two columns are read-only'); }
  function importCsv(text, name) {
    const res = M.fromCsv(text, S.doc);
    const next = JSON.parse(snapshot());
    next.nodes = res.nodes;
    const diff = M.diffNodes(S.doc.nodes, res.nodes);
    const issues = res.nodes.length ? M.check(next, S.picks) : [];
    const errs = M.errorsOf(issues);
    const few = (list) => (list.length > 12 ? list.slice(0, 12).join(', ') + ` and ${list.length - 12} more` : list.join(', '));
    const body = el('div', { class: 'trl-import' },
      el('p', { text: `${name}: ${res.rows} row${res.rows === 1 ? '' : 's'} read (separator "${res.sep === '\t' ? 'tab' : res.sep}").` }),
      res.problems.length ? el('ul', { class: 'warn-text' }, res.problems.map((p) => el('li', { text: p }))) : null,
      el('p', {}, el('b', { text: `Added ${diff.added.length}` }), diff.added.length ? `: ${few(diff.added)}` : ''),
      el('p', {}, el('b', { text: `Removed ${diff.removed.length}` }), diff.removed.length ? `: ${few(diff.removed)}` : ''),
      el('p', {}, el('b', { text: `Changed ${diff.changed.length}` }), diff.changed.length ? `: ${few(diff.changed.map((c) => `${c.id} (${c.keys.join(', ')})`))}` : ''),
      el('p', { class: 'muted', text: `${diff.same} unchanged${diff.moved ? '; the order of some nodes changed' : ''}${res.new_ids.length ? `; ${res.new_ids.length} row${res.new_ids.length === 1 ? '' : 's'} without an id got ${few(res.new_ids)}` : ''}.` }),
      el('p', {}, el('b', { text: `Checks on the result: ${errs.length} error${errs.length === 1 ? '' : 's'}, ${issues.length - errs.length} warning${issues.length - errs.length === 1 ? '' : 's'}` })),
      issues.length ? el('ul', { class: 'trl-import-list' }, issues.slice(0, 40).map((x) => el('li', { class: x.sev === 'error' ? 'warn-text' : 'muted', text: x.text }))) : null);
    const nothing = !res.nodes.length || (!diff.added.length && !diff.removed.length && !diff.changed.length && !diff.moved);
    modal('Import the Trail from a CSV', body, nothing ? [['Close', null]] : [
      [errs.length ? `Apply anyway (${errs.length} error${errs.length === 1 ? '' : 's'} to fix before Save)` : 'Apply', () => { edit((d) => { d.nodes = res.nodes; }); App.status(`Imported ${name}: ${diff.added.length} added, ${diff.removed.length} removed, ${diff.changed.length} changed (Ctrl+Z undoes it; nothing is saved yet)`, 'good'); }, 'primary'],
      ['Cancel', null]]);
  }
  function editJson() {
    if (typeof JsonEdit === 'undefined') return;
    JsonEdit.modal({ title: 'trail.json', value: S.doc, note: 'The whole file as it will be written. Apply takes what is typed as one undoable edit.', onApply: (v) => { if (!v || typeof v !== 'object' || Array.isArray(v)) return 'the Trail is a JSON object'; edit(() => { S.doc = M.normalise(v); }); return ''; } });
  }

  // ------------------------------------------------------------------ the page

  function build(panel) {
    clear(panel);
    const file = el('input', { type: 'file', accept: '.csv,text/csv,text/plain', hidden: true });
    file.addEventListener('change', () => { const f = file.files && file.files[0]; if (!f) return; const rd = new FileReader(); rd.onload = () => importCsv(String(rd.result || ''), f.name); rd.readAsText(f); file.value = ''; });
    R = { rows: new Map() };
    R.bar = el('div', { class: 'trl-top' });
    R.lbar = el('div', { class: 'trl-lbar' });
    R.motifs = el('div', { class: 'trl-layer' }); R.dark = el('div', { class: 'trl-dark' }); R.rails = el('div', { class: 'trl-layer' }); R.plates = el('div', { class: 'trl-layer' }); R.tiles = el('div', { class: 'trl-layer' });
    R.track = el('div', { class: 'trl-track' }, R.motifs, R.dark, R.rails, R.plates, R.tiles);
    R.sizer = el('div', { class: 'trl-sizer' }, R.track);
    R.view = el('div', { class: 'trl-view' }, R.sizer);
    R.top = el('div', { class: 'trl-blocks' }); R.tools = el('div', { class: 'trl-tools-host' }); R.levels = el('div', { class: 'trl-levels' });
    R.right = el('div', { class: 'trl-right' }, R.top, R.tools, R.levels);
    R.file = file;
    panel.append(R.bar, el('div', { class: 'trl-split' }, el('div', { class: 'trl-left' }, R.lbar, R.view), R.right), file);
    let raf = 0;
    R.view.addEventListener('scroll', () => { if (!raf) raf = requestAnimationFrame(() => { raf = 0; windowRows(); backdrop(); }); });
    if (typeof ResizeObserver !== 'undefined') new ResizeObserver(() => { if (S.doc && R.view.clientWidth) drawTrack(); }).observe(R.view);
    built = true;
  }
  function drawBars() {
    clear(R.bar); clear(R.lbar);
    const { issues, errors, ix, st } = S.d;
    const d = dirty();
    put(R.bar, el('h2', { text: 'The Trail' }),
      el('button', { class: 'btn primary' + (d && errors ? ' blocked' : ''), type: 'button', text: S.saving ? 'Saving…' : 'Save', disabled: S.saving || !d, title: errors ? `${errors} error(s) block the save (see Checks)` : 'write trail.json (Ctrl+S); the game needs no import', onclick: save }),
      btn('Undo', 'undo the last edit (Ctrl+Z)', undo, S.undo.length ? '' : 'off'), btn('Redo', 'redo (Ctrl+Y)', redo, S.redo.length ? '' : 'off'),
      btn('Revert', 'back to the file as it was read', () => { if (dirty()) edit(() => { S.doc = M.normalise(JSON.parse(S.base)); }); }, 'ghost' + (d ? '' : ' off')),
      btn('Reload', 'read trail.json again (unsaved edits are lost)', () => { if (!dirty() || window.confirm('Reload trail.json? The unsaved edits on this tab are lost.')) { S.doc = null; load(true); } }, 'ghost'),
      el('span', { class: 'trl-sep' }),
      btn('Export CSV', 'one row per node, for a spreadsheet', exportCsv), btn('Import CSV', 'the same table back: checked, summarised, then applied', () => R.file.click()),
      btn('JSON', 'the whole file as text', editJson, 'ghost'),
      el('span', { class: 'issues ' + (errors ? 'bad' : issues.length ? 'warn' : 'good'), title: 'what the checks say (the Checks block lists them)', onclick: () => { S.open.checks = true; store('open', JSON.stringify(S.open)); drawRight(); R.right.scrollTop = 0; }, text: errors ? `${errors} error${errors === 1 ? '' : 's'}` : issues.length ? `${issues.length} warning${issues.length === 1 ? '' : 's'}` : 'no issues' }),
      d ? el('span', { class: 'achip warn', text: 'unsaved' }) : null,
      el('span', { class: 'muted small', text: `${S.file} · ${ix.nodes.length} nodes · ${ix.max} levels` }));
    const setLevel = (v) => { S.level = Math.max(0, Math.min(ix.max, Math.round(Number(v) || 0))); derive(); later(); };
    const num = el('input', { type: 'number', class: 'trl-in n', min: 0, max: ix.max, value: String(S.level), style: 'width:58px', title: 'the Trail Level the picture shows: every required node up to it bought, the line just above the next level' });
    num.dataset.cell = 'bar|level';
    num.addEventListener('change', () => setLevel(num.value));
    const rng = el('input', { type: 'range', min: 0, max: Math.max(1, ix.max), value: String(S.level), class: 'trl-range' });
    rng.addEventListener('input', () => { S.level = Number(rng.value); num.value = rng.value; derive(); drawTrack(); });
    put(R.lbar, el('span', { text: 'Shown at Trail Level' }), num, rng,
      el('label', { class: 'trl-check', title: 'each node’s price under its tile (the game shows it on the buy card)' }, el('input', { type: 'checkbox', checked: S.showPrices, onchange: (e) => { S.showPrices = e.target.checked; store('prices', S.showPrices ? '1' : '0'); drawTrack(); } }), 'prices'),
      st.level !== st.want ? el('span', { class: 'achip warn', text: `the rules give level ${st.level}`, title: 'with these nodes bought the Trail Level comes out different: a level is done early or cannot be done (see Checks)' }) : null,
      S.link ? el('span', { class: 'trl-linking' }, `Connecting ${S.link}: click the nodes it connects from `, btn('Done', 'Esc', () => { S.link = null; later(); }, 'primary')) : null);
  }

  function render(panel) {
    panelEl = panel;
    if (!M) { clear(panel); panel.appendChild(el('p', { class: 'warn-text', text: 'trail_model.js did not load' })); return; }
    load(false);
    if (S.failed) { built = false; clear(panel); panel.append(el('h2', { text: 'The Trail' }), el('p', { class: 'warn-text', text: S.failed }), btn('Try again', '', () => { S.failed = null; load(true); redraw(); })); return; }
    if (!S.doc) { built = false; clear(panel); panel.appendChild(el('p', { class: 'muted', text: 'reading the Trail…' })); return; }
    if (!built || !R.bar || !R.bar.isConnected) build(panel);
    // the cell the caret is in, to put it back after the redraw
    const ac = document.activeElement;
    const key = wantFocus || (ac && panel.contains(ac) && ac.dataset ? ac.dataset.cell : null);
    wantFocus = null;
    drawBars(); drawRight(); drawTrack();
    if (scrollLeftBottom) { scrollLeftBottom = false; R.view.scrollTop = R.view.scrollHeight; windowRows(); backdrop(); }
    if (S.sel) { const n = node(S.sel); const b = n && R.levels.querySelector(`.trl-lvl[data-level="${n.level}"]`); if (b) fill(b); }
    if (key) {
      const nid = key.split('|')[0];
      const n = node(nid);
      const b = n && R.levels.querySelector(`.trl-lvl[data-level="${n.level}"]`);
      if (b) fill(b);
      const again = panel.querySelector(`[data-cell="${key.replace(/"/g, '\\"')}"]`);
      if (again && !again.disabled) { again.focus({ preventScroll: !wantScroll(again) }); if (again.select && again.tagName === 'INPUT' && !['checkbox', 'color', 'search', 'range'].includes(again.type)) again.select(); }
    }
  }
  function wantScroll(e) { const r = e.getBoundingClientRect(), p = R.right.getBoundingClientRect(); return r.top < p.top + 40 || r.bottom > p.bottom - 10; }

  /** Keys app.js hands over while this tab shows: true when taken. */
  function key(e, typing) {
    const ctrl = e.ctrlKey || e.metaKey;
    const t = e.target;
    const mine = typing && t.dataset && t.dataset.orig !== undefined && t.value !== t.dataset.orig;   // a cell still being typed in keeps the browser's own undo
    if (ctrl && e.key.toLowerCase() === 'z' && !e.shiftKey && !mine) { e.preventDefault(); if (typing) t.blur(); undo(); return true; }
    if (ctrl && (e.key.toLowerCase() === 'y' || (e.key.toLowerCase() === 'z' && e.shiftKey)) && !mine) { e.preventDefault(); if (typing) t.blur(); redo(); return true; }
    if (e.key === 'Escape' && S.link) { S.link = null; later(); return true; }
    return false;
  }

  /** Another document shown in place of the file's, as one undoable edit (nothing is written until Save). */
  function show(doc) { if (S.doc) edit(() => { S.doc = M.normalise(doc); }); }

  return { render, save, dirty, load, key, undo, redo, show, S };
})();
if (typeof module !== 'undefined') module.exports = Trail;
