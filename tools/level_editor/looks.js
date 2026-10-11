// The look grid (pass 66, lane V): every art variant ("look") of a creature or a hero as a card with a hover-to-play
// strip preview, the chips that say what it is (the default in play, NEW = painted by a job and not yet looked at,
// shelved = kept but out of the arena and the default lists, not imported, stub = an entry without a strip yet), its
// note, and the actions Garry asked for ("everything is reviewed ... and approved, all in this LevelEditor"): Make
// default, Approve, Shelve / Unshelve, Remove, Edit note / recipe, Re-roll… (the job form pre-filled), Icon candidates….
// Built for ~50 looks of one creature (interview answer 3): a filter box, a status filter, pages of 24, ☐ select with
// bulk Shelve / Unshelve / Remove. One `controls` player above the grid plays the selected look with every animation and
// direction. Every action is one POST /api/content/<kind>/<id>/look/<code> {op} (the server writes the JSON after a
// backup and imports it); the record is refreshed through Assets.refreshRecord when lane P's module has it, else
// re-fetched, and the one card is redrawn in place.
//
//   LookGrid.render(container, record, doc, {kind, id, onSelect, newButton})   record = /api/enemies' creature record
//   (variants[] / looks[]) or /api/heroes' hero record (looks[]); doc = the open document (unused here, kept for P)
//   LookGrid.select(code)   land on a look (a toast's "open look" button, the Jobs tab's "Open look")
'use strict';

const LookGrid = (() => {
  const { el, clear } = U;
  const PAGE = 24;
  const STATUS = [
    { v: 'all', label: 'all' }, { v: 'playable', label: 'playable' }, { v: 'new', label: 'new' }, { v: 'shelved', label: 'shelved' },
    { v: 'unpainted', label: 'not painted' }, { v: 'unimported', label: 'not imported' },
  ];
  const states = new Map();     // `${kind}|${id}` -> the grid's view state (survives the pane's re-renders)
  let pendingSelect = null;     // {kind, id, code}: select() before the grid shows
  let current = null;           // {kind, id, container, record, opts}: the grid on screen

  function playerKind(kind) { return kind === 'hero' ? 'hero' : 'enemy'; }
  function looksOf(record) { return Array.isArray(record.looks) ? record.looks : (Array.isArray(record.variants) ? record.variants : []); }
  function playCode(record) { return record.play || record.variant || record.variant_base || ''; }
  function isDefault(look, record) { return look.default === true || look.code === playCode(record); }
  function isStub(look) { return look.ready === false && !look.base; }
  /** "Flux.2 dev · 28 passes · guidance 4 · no Turbo": a look's recorded painter (variants[CODE].recipe.painter, written
   *  by its job; absent on looks painted before it was kept). */
  function painterText(p) {
    if (!p || typeof p !== 'object') return '';
    const dev = p.model === 'dev';
    const bits = [dev ? 'Flux.2 dev' : 'Flux.2 Klein', p.steps ? `${p.steps} passes` : (dev ? (p.turbo === false ? '28 passes (default)' : '8 passes (default)') : '4 passes (default)')];
    if (dev) { if (p.guidance) bits.push(`guidance ${p.guidance}`); bits.push(p.turbo === false ? 'no Turbo' : 'Turbo'); }
    return bits.join(' · ');
  }
  /** The method a look was painted with: its recipe's `method`, else what the open document's words imply (Assets.methodOf). */
  function methodOf(look) {
    if (look.recipe && look.recipe.method) return String(look.recipe.method);
    if (current && current.doc && typeof Assets !== 'undefined' && typeof Assets.methodOf === 'function') { try { return Assets.methodOf(current.doc, look.code); } catch (_) { /* fall through */ } }
    return '';
  }
  /** The recipe's own keys apart from the bookkeeping ones (painter, method). */
  function ownKeys(look) { return Object.keys(look.recipe && typeof look.recipe === 'object' ? look.recipe : {}).filter((k) => !['painter', 'method'].includes(k)); }
  /** The words the painting followed: the recipe's, else the creature's own (the open document's data). */
  function wordsOf(look) {
    const rec = look.recipe || {};
    const base = current && current.doc && current.doc.data ? current.doc.data : {};
    const own = rec.art_prompt || rec.prompt;
    if (own) return { text: String(own), src: 'own' };
    const inh = base.art_prompt || base.prompt;
    return inh ? { text: String(inh), src: 'inherited' } : { text: '', src: '' };
  }
  function st(kind, id) {
    const k = `${kind}|${id}`;
    if (!states.has(k)) states.set(k, { filter: '', status: 'all', page: 0, selected: null, selectMode: false, checked: new Set(), confirm: null, edit: null, busy: false, players: new Map(), stage: null });
    return states.get(k);
  }

  /** The StripPlayer options for one look of a record (the look's own anims / fps / strip_cols / frame_px, else the
   *  record's; a hero's cell is 1.9 m; `?v=<sprite_mtime>` busts the strip's 60 s cache). */
  function playerOpts(kind, record, look, extra) {
    const pk = playerKind(kind);
    return Object.assign({
      url: look.sprite || '', mtime: look.sprite_mtime, kind: pk,
      framePx: look.frame_px || record.frame_px || (pk === 'hero' ? 256 : 128),
      anims: look.anims || record.anims || {}, stripCols: look.strip_cols || record.strip_cols || 0, fps: look.fps || record.fps || {},
      // a hero's quad is always 1.9 m (Player.gd:165), whatever `size` his JSON carries for other uses
      size: pk === 'hero' ? StripPlayer.HERO_SIZE : (record.size || 1.5),
      frontFaces: look.front_faces || record.front_faces || 'right', backFaces: look.back_faces || record.back_faces || 'right',
      shadow: record.shadow || null, label: `${record.name || record.id} · ${look.code}`,
    }, extra || {});
  }

  function matches(look, record, s) {
    if (s.filter) {
      const f = s.filter.toLowerCase();
      if (!(String(look.code).toLowerCase().includes(f) || String(look.note || '').toLowerCase().includes(f))) return false;
    }
    switch (s.status) {
      case 'playable': return look.ready !== false && !look.shelved;
      case 'new': return !!look.fresh;
      case 'shelved': return !!look.shelved;
      case 'unpainted': return isStub(look);
      case 'unimported': return look.imported === false;
      default: return true;
    }
  }

  function sorted(looks, record) {
    return looks.slice().sort((a, b) => (isDefault(b, record) - isDefault(a, record)) || ((a.shelved ? 1 : 0) - (b.shelved ? 1 : 0)) || String(a.code).localeCompare(String(b.code), undefined, { numeric: true }));
  }

  // ------------------------------------------------------------------ render

  function render(container, record, doc, opts) {
    const o = opts || {};
    const kind = o.kind || record.kind || 'enemy';
    const id = o.id || record.id;
    const s = st(kind, id);
    current = { kind, id, container, record, opts: o, doc };
    clear(container);
    container.classList.add('lookgrid');
    const looks = sorted(looksOf(record), record);
    if (pendingSelect && pendingSelect.kind === kind && pendingSelect.id === id) { s.selected = pendingSelect.code; pendingSelect = null; }
    else if (o.selected && looks.some((l) => l.code === o.selected)) s.selected = o.selected;   // the document's own choice (lane P's doc.ui.look)
    if (!s.selected || !looks.some((l) => l.code === s.selected)) s.selected = playCode(record) || (looks[0] && looks[0].code) || null;

    // the stage: one controls player for the selected look
    container.appendChild(stage(kind, id, record, looks, s));

    // the header
    const nShelved = looks.filter((l) => l.shelved).length, nNew = looks.filter((l) => l.fresh).length;
    const head = el('div', { class: 'lg-head' });
    head.appendChild(el('h3', { text: `Looks · ${looks.length}` }));
    head.appendChild(el('span', { class: 'count', text: looks.length ? `(${nShelved} shelved, ${nNew} new)` : '(none yet)' }));
    const box = el('input', { type: 'search', class: 'txt', placeholder: 'filter by code or note…', value: s.filter, title: 'show the looks whose code or note contains this' });
    box.addEventListener('input', () => { s.filter = box.value.trim(); s.page = 0; drawGrid(); });
    head.appendChild(box);
    const sel = el('select', { title: 'which looks to show' });
    for (const x of STATUS) sel.appendChild(el('option', { value: x.v, text: x.label, selected: x.v === s.status }));
    sel.addEventListener('change', () => { s.status = sel.value; s.page = 0; drawGrid(); });
    head.appendChild(sel);
    const cb = el('input', { type: 'checkbox' }); cb.checked = s.selectMode;
    cb.addEventListener('change', () => { s.selectMode = cb.checked; if (!cb.checked) s.checked.clear(); drawGrid(); });
    head.appendChild(el('label', { class: 'cb', title: 'tick looks, then shelve, unshelve or remove them together' }, cb, el('span', { text: 'select' })));
    if (o.newButton !== false) head.appendChild(el('button', { type: 'button', class: 'btn small primary', text: '+ New look…', title: 'queue an art job for one or more new looks of this ' + (kind === 'hero' ? 'hero' : 'creature'), onclick: () => openForm(kind, id, { mode: 'look' }) }));
    head.appendChild(el('span', { class: 'muted small', text: 'hover a card to play it · click it for the player above · double-click for the close look' }));
    container.appendChild(head);

    const bulk = el('div', { class: 'lg-bulk', hidden: true });
    container.appendChild(bulk);
    const grid = el('div', { class: 'lg-grid' });
    container.appendChild(grid);
    const pages = el('div', { class: 'lg-pages' });
    container.appendChild(pages);
    drawGrid();
    return container;

    function drawGrid() {
      // drop the players of looks that are gone
      const have = new Set(looks.map((l) => l.code));
      for (const [code, p] of s.players) if (!have.has(code)) { p.destroy(); s.players.delete(code); }
      const shown = looks.filter((l) => matches(l, record, s));
      const nPages = Math.max(1, Math.ceil(shown.length / PAGE));
      if (s.page >= nPages) s.page = nPages - 1;
      const page = shown.slice(s.page * PAGE, (s.page + 1) * PAGE);
      // detach the players of cards leaving the page (they keep their state; the LRU may drop their strips)
      clear(grid);
      if (!shown.length) grid.appendChild(el('div', { class: 'placeholder muted', style: 'grid-column: 1 / -1; padding: 14px;', text: looks.length ? 'no look matches the filter' : 'no looks yet: + New look… queues the first' }));
      for (const look of page) grid.appendChild(card(kind, id, record, look, s));
      if (s.confirm) grid.appendChild(confirmBox(kind, id, record, s));
      if (s.edit) grid.appendChild(editBox(kind, id, record, s));
      // pages
      clear(pages);
      if (nPages > 1) {
        pages.appendChild(el('button', { type: 'button', class: 'btn small', text: '‹', disabled: s.page === 0, onclick: () => { s.page--; drawGrid(); } }));
        for (let i = 0; i < nPages; i++) pages.appendChild(el('button', { type: 'button', class: 'btn small' + (i === s.page ? ' on' : ''), text: String(i + 1), onclick: () => { s.page = i; drawGrid(); } }));
        pages.appendChild(el('button', { type: 'button', class: 'btn small', text: '›', disabled: s.page >= nPages - 1, onclick: () => { s.page++; drawGrid(); } }));
        pages.appendChild(el('span', { class: 'muted small', text: ` ${shown.length} looks, ${PAGE} a page` }));
      }
      // the bulk bar
      clear(bulk);
      bulk.hidden = !s.selectMode;
      if (s.selectMode) {
        const n = s.checked.size;
        bulk.appendChild(el('span', { text: `Selected ${n}:` }));
        bulk.appendChild(el('button', { type: 'button', class: 'btn small', text: 'Shelve', disabled: !n || s.busy, onclick: () => bulkOp(kind, id, record, s, 'shelve') }));
        bulk.appendChild(el('button', { type: 'button', class: 'btn small', text: 'Unshelve', disabled: !n || s.busy, onclick: () => bulkOp(kind, id, record, s, 'unshelve') }));
        bulk.appendChild(el('button', { type: 'button', class: 'btn small danger', text: 'Remove', disabled: !n || s.busy, onclick: () => { s.confirm = { codes: [...s.checked] }; drawGrid(); } }));
        bulk.appendChild(el('button', { type: 'button', class: 'btn small ghost', text: n === shown.length ? 'none' : 'all shown', onclick: () => { if (n === shown.length) s.checked.clear(); else for (const l of shown) s.checked.add(l.code); drawGrid(); } }));
        bulk.appendChild(el('span', { class: 'muted small', text: 'the look in play cannot be shelved or removed' }));
      }
    }
  }

  /** The player above the grid for the selected look, with the look's facts beside it. */
  function stage(kind, id, record, looks, s) {
    const wrap = el('div', { class: 'lg-stage' });
    const look = looks.find((l) => l.code === s.selected) || looks[0];
    if (!look) { wrap.appendChild(el('span', { class: 'muted', text: 'no looks: the game plays the top-level strip' })); return wrap; }
    const opts = playerOpts(kind, record, look, { mode: 'controls', zoom: 1 });
    if (s.stage && !s.stage.destroyed) { s.stage.setStrip(opts); }
    else s.stage = StripPlayer.create(opts);
    wrap.appendChild(s.stage.el);
    const info = el('div', { class: 'lg-stage-info' });
    const chips = chipsFor(look, record);
    info.appendChild(el('h3', {}, el('span', { text: look.code }), ...chips));
    if (look.note) info.appendChild(el('div', { class: 'note', text: look.note }));
    const anims = look.anims || record.anims || {};
    const keys = Object.keys(anims).filter((k) => anims[k] > 0);
    const dl = el('dl');
    const row = (k, v, title) => { dl.appendChild(el('dt', { text: k, title: title || '' })); dl.appendChild(el('dd', { text: v, title: title || '' })); };
    row('strip', look.sprite ? String(look.sprite).split('?')[0] : '—', 'the strip the server serves for this look');
    row('frames', `${StripPlayer.totalFrames(anims)} in ${keys.length} animations · ${look.strip_cols || record.strip_cols || 'one row'} cols · ${look.frame_px || record.frame_px || (kind === 'hero' ? 256 : 128)} px cells`);
    row('directions', anims.run_s > 0 ? '8 (side and three-quarter views painted)' : '2 (front and back; the game mirrors for heading left)');
    row('fps', JSON.stringify(look.fps || record.fps || {}) + ' (run and die from the JSON; the rest preview rates)');
    if (look.head != null) row('head', String(look.head), 'where the head sits in the cell (0..1 from the top), for the hit flash and the elite crown');
    if (look.imported === false) row('import', 'not imported: the game still plays the old .tres (Save or a finished job imports)');
    // the recipe: what differs from the creature's own words, the painter it ran with, the words it followed
    const own = ownKeys(look);
    const method = methodOf(look);
    if (look.base && !own.length) row('recipe', 'the base strip: the creature\'s own art words (the Art section) are its recipe' + (method ? ` · ${method}` : ''), 'the top-level strip has no recipe of its own');
    else if (!own.length) row('recipe', 'no recipe recorded' + (method ? ` · ${method} (implied)` : ''), 'painted before the Level Editor kept recipes, by hand, or by a job with an empty recipe: the creature\'s own words are what a job for this code would read now; Duplicate… starts a new look from them');
    else row('recipe', `${method || 'method implied'} · ${own.length} own key${own.length === 1 ? '' : 's'} (${own.slice(0, 6).join(', ')}${own.length > 6 ? ', …' : ''}); the rest inherited from the creature`, 'Recipe (typed)… shows every field with its source: own, inherited or the method\'s default');
    const w = wordsOf(look);
    if (w.text) row('words', (w.text.length > 150 ? w.text.slice(0, 150) + '…' : w.text) + (w.src === 'inherited' ? ' (the creature\'s own)' : ''), w.text);
    const painter = look.recipe && look.recipe.painter;
    row('painter', painter ? painterText(painter) : 'not recorded (painted before the painter was kept: Flux.2 Klein with its defaults unless the job said dev)', 'the model and the passes the stills were painted with (the job form\'s Model settings, kept in variants[CODE].recipe.painter)');
    info.appendChild(dl);
    const acts = el('div', { class: 'lg-actions' });
    actions(acts, kind, id, record, look, s);
    info.appendChild(acts);
    wrap.appendChild(info);
    return wrap;
  }

  function chipsFor(look, record) {
    const out = [];
    if (isDefault(look, record)) out.push(el('span', { class: 'chip default', text: '● default', title: 'the look the game plays for every row that names none (the JSON\'s `variant`)' }));
    if (look.base) out.push(el('span', { class: 'chip base', text: 'base', title: 'the top-level strip of the JSON (variant_base)' }));
    if (look.fresh) out.push(el('span', { class: 'chip new', text: 'NEW', title: 'painted by a job and not yet approved: Approve clears the mark (the game ignores it)' }));
    if (look.shelved) out.push(el('span', { class: 'chip shelved', text: 'shelved', title: 'kept in the JSON but hidden from the arena chips and the default lists (variants[CODE].shelved); a row naming it still plays it' }));
    if (look.imported === false) out.push(el('span', { class: 'chip notimported', text: 'not imported', title: 'the strip\'s .import or the .tres is older than the files: the game plays the old data until an import runs' }));
    if (isStub(look)) out.push(el('span', { class: 'chip stub', text: 'stub', title: 'no sprite yet: a job\'s placeholder entry (queued, running, failed or cancelled); the game skips it' }));
    const jobs = typeof Jobs !== 'undefined' && Jobs.jobsFor ? Jobs.jobsFor(record.kind || 'enemy', record.id, look.code) : [];
    for (const j of jobs) if (['queued', 'running', 'waiting'].includes(j.state)) out.push(el('button', { type: 'button', class: 'chip state-' + j.state, text: j.state === 'waiting' ? 'needs a pick' : j.state, title: `${j.title || j.id}: open the Jobs tab`, onclick: (e) => { e.stopPropagation(); App.switchTab('jobs'); } }));
    return out;
  }

  function card(kind, id, record, look, s) {
    const c = el('article', { class: 'lg-card' + (look.code === s.selected ? ' selected' : '') + (look.shelved ? ' shelved' : '') + (isStub(look) ? ' stub' : ''), 'data-code': look.code });
    const top = el('div', { class: 'lg-card-top' }, el('b', { text: look.code }), ...chipsFor(look, record));
    if (s.selectMode) {
      const cb = el('input', { type: 'checkbox', checked: s.checked.has(look.code), onclick: (e) => e.stopPropagation() });
      cb.addEventListener('change', () => { if (cb.checked) s.checked.add(look.code); else s.checked.delete(look.code); const n = s.checked.size; const bar = c.closest('.lookgrid').querySelector('.lg-bulk span'); if (bar) bar.textContent = `Selected ${n}:`; for (const b of c.closest('.lookgrid').querySelectorAll('.lg-bulk .btn:not(.ghost)')) b.disabled = !n; });
      top.appendChild(el('label', { class: 'cb' }, cb));
    }
    c.appendChild(top);
    const pic = el('div', { class: 'lg-pic' });
    if (isStub(look)) pic.appendChild(el('div', { class: 'placeholder', text: 'no sprite yet' }));
    else {
      let p = s.players.get(look.code);
      const opts = playerOpts(kind, record, look, { mode: 'hover', zoom: 0.5 });
      if (p && !p.destroyed) { if (p.url.split('?')[0] !== String(opts.url).split('?')[0] || (opts.mtime != null && !p.url.endsWith('v=' + encodeURIComponent(opts.mtime)))) p.setStrip(opts); }
      else { p = StripPlayer.create(opts); s.players.set(look.code, p); }
      pic.appendChild(p.el);
    }
    c.appendChild(pic);
    c.appendChild(el('div', { class: 'lg-note', text: look.note || '', title: look.note || '' }));
    const painter = look.recipe && look.recipe.painter;
    const own = ownKeys(look);
    const method = methodOf(look);
    const meta = look.base && !own.length ? 'the creature\'s own words' : (!own.length ? 'no recipe recorded' : `${own.length} own key${own.length === 1 ? '' : 's'}`);
    c.appendChild(el('div', { class: 'lg-meta', text: `${method || '?'} · ${meta}${painter ? ' · ' + (painter.model === 'dev' ? 'dev' : 'Klein') + (painter.steps ? ' ' + painter.steps : '') : ''}`,
      title: `${method ? 'method ' + method : 'the method is not recorded'} · ${meta}${painter ? ' · painted with ' + painterText(painter) : ' · the painter was not recorded'}` }));
    const acts = el('div', { class: 'lg-actions' });
    actions(acts, kind, id, record, look, s);
    c.appendChild(acts);
    c.addEventListener('click', (e) => {
      if (e.target.closest('button, input, label, select')) return;
      s.selected = look.code;
      if (current && current.container) {
        for (const x of current.container.querySelectorAll('.lg-card')) x.classList.toggle('selected', x.dataset.code === look.code);
        const stageEl = current.container.querySelector('.lg-stage');
        if (stageEl) stageEl.replaceWith(stage(kind, id, record, sorted(looksOf(record), record), s));
      }
      if (current && current.opts.onSelect) current.opts.onSelect(look.code, look);
    });
    return c;
  }

  function actions(host, kind, id, record, look, s) {
    const def = isDefault(look, record);
    const b = (text, title, fn, cls) => host.appendChild(el('button', { type: 'button', class: 'btn small ghost' + (cls ? ' ' + cls : ''), text, title, disabled: s.busy, onclick: (e) => { e.stopPropagation(); fn(); } }));
    if (!def) {
      if (look.ready !== false && !look.shelved) b('Make default', `write "variant": "${look.code}" in ${id}.json (after a backup) and import it: every row that names no look plays it`, () => op(kind, id, record, s, look.code, { op: 'default' }));
    }
    if (look.fresh) b('Approve', 'you looked at it and it stays: clears the NEW mark (deletes variants[CODE].fresh; the game never read it)', () => op(kind, id, record, s, look.code, { op: 'approve' }));
    if (!look.shelved) {
      if (def) host.appendChild(el('span', { class: 'muted', text: 'Shelve', title: 'the look in play cannot be shelved: make another the default first' }));
      else b('Shelve', 'keep it, but hide it from the arena chips and the default lists (variants[CODE].shelved = true)', () => op(kind, id, record, s, look.code, { op: 'shelve' }));
    } else b('Unshelve', 'show it in the arena and the lists again', () => op(kind, id, record, s, look.code, { op: 'unshelve' }));
    if (def || look.base) host.appendChild(el('span', { class: 'muted', text: 'Remove', title: def ? 'the look in play cannot be removed' : 'the base strip cannot be removed' }));
    else b('Remove', 'delete the entry; its PNGs and .import files move to tools/level_editor/backups/deleted/<id>/<stamp>/ (refused while a map row names it)', () => { s.confirm = { codes: [look.code] }; redraw(); }, 'danger');
    b('Edit note / recipe', 'the note shown on the cards and the recipe the art job reads (raw JSON)', () => { s.edit = { code: look.code, note: look.note || '', recipe: look.recipe || null }; redraw(); });
    if (current && current.doc && typeof Assets !== 'undefined' && typeof Assets.recipeEditor === 'function') b('Recipe (typed)…', 'the recipe as typed fields per method (the editor pane\'s own editor)', () => Assets.recipeEditor(current.doc, look.code));
    b('Re-roll…', 'queue the look again: the job form opens with its recipe and painter (new seeds, redo the clips, one view, or repaint the stills)', () => openForm(kind, id, { mode: 'look', code: look.code, method: methodOf(look) || undefined, recipe: look.recipe || null, painter: (look.recipe && look.recipe.painter) || null, reroll: true }));
    b('Duplicate…', 'a new look from this one: the job form opens with its recipe, its words and its painter copied and a new code; change the model, the passes or any field, then Queue (the stills are painted again unless you tick "reuse the paintings")', () => openForm(kind, id, { mode: 'look', method: methodOf(look) || undefined, recipe: look.recipe || null, painter: (look.recipe && look.recipe.painter) || null, duplicateOf: look.code, note: look.note || '' }));
    b('Icon candidates…', 'paint icon candidates for this look to pick from (the default icon is a crop of the front still)', () => openForm(kind, id, { mode: 'icon', code: look.code }));
  }

  function confirmBox(kind, id, record, s) {
    const codes = s.confirm.codes;
    const box = el('div', { class: 'lg-confirm' });
    box.appendChild(el('span', { text: `Remove ${codes.join(', ')} from ${record.name || id}? The entr${codes.length > 1 ? 'ies go' : 'y goes'} out of ${id}.json (after a backup); the PNGs and their .import files move to tools/level_editor/backups/deleted/${id}/<stamp>/; then an import runs. The server refuses the look in play and any look a map row names.` }));
    box.appendChild(el('button', { type: 'button', class: 'btn small danger', text: s.busy ? 'Removing…' : `Yes, remove ${codes.length > 1 ? codes.length + ' looks' : codes[0]}`, disabled: s.busy, onclick: () => { s.confirm = null; if (codes.length === 1) op(kind, id, record, s, codes[0], { op: 'remove' }); else bulkOp(kind, id, record, s, 'remove', codes); } }));
    box.appendChild(el('button', { type: 'button', class: 'btn small ghost', text: 'Cancel', onclick: () => { s.confirm = null; redraw(); } }));
    return box;
  }

  function editBox(kind, id, record, s) {
    const e = s.edit;
    const box = el('div', { class: 'lg-edit' });
    box.appendChild(el('b', { text: `${e.code}: note and recipe` }));
    const note = el('input', { type: 'text', class: 'txt wide', value: e.note, placeholder: 'what this look is, in a line (shown on the cards and the arena chips)' });
    box.appendChild(el('div', { class: 'row' }, el('span', { class: 'muted small', text: 'note' }), note));
    const ta = el('textarea', { class: 'mono', spellcheck: false, placeholder: '{ "method": "creature_pose2", "pose": "walk_zombie", ... }  (the keys the art job reads; empty = none)' });
    ta.value = e.recipe ? JSON.stringify(e.recipe, null, 2) : '';
    const err = el('span', { class: 'warn-text small' });
    ta.addEventListener('input', () => { try { if (ta.value.trim()) JSON.parse(ta.value); err.textContent = ''; } catch (x) { err.textContent = 'not JSON: ' + x.message; } });
    box.appendChild(el('div', { class: 'row' }, el('span', { class: 'muted small', text: 'recipe (JSON)' }), err));
    box.appendChild(ta);
    box.appendChild(el('div', { class: 'muted small', text: 'The recipe is tool-only: gen_art / gen_ctl read it when a job runs for this code; the game ignores it. The job form writes typed fields into it; this box is the raw view.' }));
    box.appendChild(el('div', { class: 'row' },
      el('button', { type: 'button', class: 'btn small primary', text: s.busy ? 'Saving…' : 'Save', disabled: s.busy, onclick: async () => {
        let recipe = null;
        if (ta.value.trim()) { try { recipe = JSON.parse(ta.value); } catch (x) { err.textContent = 'not JSON: ' + x.message; return; } }
        const ops = [];
        if (note.value.trim() !== (e.note || '')) ops.push({ op: 'note', note: note.value.trim() });
        if (JSON.stringify(recipe) !== JSON.stringify(e.recipe || null)) ops.push({ op: 'recipe', recipe });
        s.edit = null;
        if (!ops.length) { redraw(); return; }
        for (const body of ops) await op(kind, id, record, s, e.code, body, true);
        await refresh(kind, id, record, s);
      } }),
      el('button', { type: 'button', class: 'btn small ghost', text: 'Cancel', onclick: () => { s.edit = null; redraw(); } })));
    return box;
  }

  // ------------------------------------------------------------------ the server

  async function post(url, body) {
    const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    let res = null;
    try { res = await r.json(); } catch (_) { res = { ok: false, error: `HTTP ${r.status}` }; }
    if (!r.ok && res && res.ok !== false) res.ok = false;
    if (res && !res.ok && !res.error) res.error = `HTTP ${r.status}`;
    if (res && res.refs) res.error = (res.error || 'refused') + ': named by ' + (Array.isArray(res.refs) ? res.refs.join(', ') : JSON.stringify(res.refs));
    return res;
  }

  async function op(kind, id, record, s, code, body, quiet) {
    s.busy = true;
    redraw();
    App.status(`${record.name || id}: ${body.op} ${code}…`, 'busy');
    if (current && current.opts && typeof current.opts.lookOp === 'function') {
      // the document's own routine (lane P): it posts, refreshes the record and redraws the pane (this grid with it)
      const ok = await current.opts.lookOp(code, body);
      s.busy = false;
      redraw();                      // the pane was redrawn while busy was set (disabled buttons): draw it again
      if (ok) App.status(`${record.name || id} ${code}: ${body.op} done`, 'good');
      return { ok: !!ok };
    }
    const res = await post(`/api/content/${encodeURIComponent(kind)}/${encodeURIComponent(id)}/look/${encodeURIComponent(code)}`, body);
    s.busy = false;
    if (!res.ok) { App.status(`${id} ${code}: ${body.op} refused: ${res.error}`, 'bad', res.output || ''); redraw(); return res; }
    if (res.import_ok === false) App.status(`${id} ${code}: ${body.op} written · IMPORT FAILED (the game plays the old .tres)`, 'bad', res.output || '');
    else App.status(`${id} ${code}: ${body.op} done${res.import_ok ? ' · import OK' : ''}${res.backup ? ' · backup ' + String(res.backup).split(/[\\/]/).pop() : ''}`, 'good', res.output || '');
    if (!quiet) await refresh(kind, id, record, s, res.looks, code, body.op);
    return res;
  }

  async function bulkOp(kind, id, record, s, opName, codes) {
    const list = codes || [...s.checked];
    if (!list.length) return;
    s.busy = true;
    redraw();
    App.status(`${record.name || id}: ${opName} ${list.length} looks…`, 'busy');
    if (current && current.opts && typeof current.opts.lookOp === 'function') {
      const ok = await current.opts.lookOp(list[0], { op: opName, codes: list });
      s.busy = false;
      if (ok) { s.checked.clear(); App.status(`${record.name || id}: ${opName} ${list.length} looks done`, 'good'); }
      redraw();
      return;
    }
    const res = await post(`/api/content/${encodeURIComponent(kind)}/${encodeURIComponent(id)}/look/${encodeURIComponent(list[0])}`, { op: opName, codes: list });
    s.busy = false;
    if (!res.ok) { App.status(`${id}: ${opName} refused: ${res.error}`, 'bad', res.output || ''); redraw(); return; }
    s.checked.clear();
    App.status(`${id}: ${opName} ${list.length} looks done${res.import_ok ? ' · import OK' : res.import_ok === false ? ' · IMPORT FAILED' : ''}`, res.import_ok === false ? 'bad' : 'good', res.output || '');
    await refresh(kind, id, record, s, res.looks);
  }

  /** The record after a change: Assets.refreshRecord (lane P) when it exists, else the list re-fetched; then the grid is
   *  drawn again (one card when only one look changed). */
  async function refresh(kind, id, record, s, looks, code, opName) {
    let fresh = null;
    try {
      if (typeof Assets !== 'undefined' && typeof Assets.refreshRecord === 'function') {
        const r = await Assets.refreshRecord(kind, id);
        if (r && r.id === id) fresh = r;
      }
      if (!fresh) {
        const url = kind === 'hero' ? '/api/heroes' : '/api/enemies';
        const r = await fetch(url, { cache: 'no-store' });
        const list = await r.json();
        fresh = Array.isArray(list) ? list.find((x) => x.id === id) : null;
      }
    } catch (e) { App.status(`${id}: refreshed in the page only (${e.message})`, 'bad'); }
    if (!fresh) {
      // keep the record, swap the looks the server returned
      fresh = Object.assign({}, record);
      if (Array.isArray(looks)) { if (Array.isArray(record.looks)) fresh.looks = looks; else fresh.variants = looks; }
    }
    if (current && current.id === id && current.kind === kind && current.container && current.container.isConnected) {
      current.record = fresh;
      const single = code && opName && opName !== 'default' && opName !== 'remove';
      if (single) updateCard(kind, id, fresh, s, code); else render(current.container, fresh, current.doc, current.opts);
    }
    if (typeof App !== 'undefined' && kind !== 'hero' && typeof App.refreshCreatures === 'function' && (opName === 'default' || opName === 'remove' || !opName)) {
      // the palette and the pickers read App.S.enemies: keep them in step (it redraws the Enemies tab when it is open)
      try { await App.refreshCreatures(); } catch (_) { /* the page shows what the server said */ }
    }
  }

  function updateCard(kind, id, record, s, code) {
    const look = looksOf(record).find((l) => l.code === code);
    const old = current.container.querySelector(`.lg-card[data-code="${code}"]`);
    if (!look || !old) { render(current.container, record, current.doc, current.opts); return; }
    old.replaceWith(card(kind, id, record, look, s));
    const stageEl = current.container.querySelector('.lg-stage');
    if (stageEl && s.selected === code) stageEl.replaceWith(stage(kind, id, record, sorted(looksOf(record), record), s));
    const head = current.container.querySelector('.lg-head .count');
    const looks = looksOf(record);
    if (head) head.textContent = `(${looks.filter((l) => l.shelved).length} shelved, ${looks.filter((l) => l.fresh).length} new)`;
  }

  function redraw() { if (current && current.container && current.container.isConnected) render(current.container, current.record, current.doc, current.opts); }

  function openForm(kind, id, o) {
    if (typeof Jobs !== 'undefined' && typeof Jobs.openForm === 'function') Jobs.openForm(kind, id, o);
    else App.toast('the job form is not here yet (jobs.js)');
  }

  /** Land on a look: selected and scrolled to when its grid is on screen, remembered for the next render otherwise. */
  function select(code, kind, id) {
    if (current && (!kind || (current.kind === kind && current.id === id))) {
      const s = st(current.kind, current.id);
      s.selected = code;
      s.filter = '';
      s.status = 'all';
      render(current.container, current.record, current.doc, current.opts);
      const c = current.container.querySelector(`.lg-card[data-code="${code}"]`);
      if (c) c.scrollIntoView({ block: 'nearest' });
      return true;
    }
    pendingSelect = { kind, id, code };
    return false;
  }

  /** Release every player of a grid that left the page (lane P may call it when a document closes). */
  function dispose(kind, id) {
    const s = states.get(`${kind}|${id}`);
    if (!s) return;
    for (const p of s.players.values()) p.destroy();
    if (s.stage) s.stage.destroy();
    states.delete(`${kind}|${id}`);
    if (current && current.kind === kind && current.id === id) current = null;
  }

  return { painterText, render, select, dispose, playerOpts, looksOf, PAGE, STATUS };
})();
