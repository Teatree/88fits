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
//
// Pass 68 (lane W): Duplicate… makes a DRAFT and starts nothing (POST /api/content/<kind>/<id>/look {note, recipe}: the
// server's add_look, the next free code, an entry without a sprite); a stub with no queued, running or waiting look job
// is a draft, with a primary Generate… that opens the job form for that code as a new look (the document saved first).
// A hero look offers badge and title cut-out candidates (a hero's icon is the round badge), a creature look icon
// candidates; the painter line says when the stills were reused rather than painted (recipe.painter.stills). The review
// fixes: the page says where the game shows a look's badge and cut-out (WHERE_SHOWN: the cut-out only on the Painted
// title); a change in the job list redraws the grid only for the asset on screen and never under the open edit or
// confirm box, and the edit box keeps what was typed through any redraw.
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
  function cap(s) { return s ? s[0].toUpperCase() + s.slice(1) : s; }
  function looksOf(record) { return Array.isArray(record.looks) ? record.looks : (Array.isArray(record.variants) ? record.variants : []); }
  function playCode(record) { return record.play || record.variant || record.variant_base || ''; }
  function isDefault(look, record) { return look.default === true || look.code === playCode(record); }
  function isStub(look) { return look.ready === false && !look.base; }
  /** The queued, running and waiting jobs of one look (all kinds: the chips show them); `lookOnly` = its look jobs. */
  function liveJobs(kind, id, code, lookOnly) {
    const list = typeof Jobs !== 'undefined' && typeof Jobs.jobsFor === 'function' ? Jobs.jobsFor(kind, id, code) : [];
    return list.filter((j) => ['queued', 'running', 'waiting'].includes(j.state) && (!lookOnly || j.kind === 'look'));
  }
  /** A draft (pass 68, D5): an entry without a sprite and without a live look job; Generate… paints it. */
  function isDraft(look, kind, id) { return isStub(look) && !liveJobs(kind, id, look.code, true).length; }
  /** "Flux.2 dev · 28 passes · guidance 4 · no Turbo": a look's recorded painter (variants[CODE].recipe.painter, written
   *  by its job; absent on looks painted before it was kept). Pass 68 (D4): the job's landing adds `stills` ("reused",
   *  or "N of M painted") when some stills were on disk already: the painter painted only the rest. */
  function painterText(p) {
    if (!p || typeof p !== 'object') return '';
    const dev = p.model === 'dev';
    const bits = [dev ? 'Flux.2 dev' : 'Flux.2 Klein', p.steps ? `${p.steps} passes` : (dev ? (p.turbo === false ? '28 passes (default)' : '8 passes (default)') : '4 passes (default)')];
    if (dev) { if (p.guidance) bits.push(`guidance ${p.guidance}`); bits.push(p.turbo === false ? 'no Turbo' : 'Turbo'); }
    if (p.stills === 'reused') bits.push('stills reused from earlier paintings: this painter painted none of them');
    else if (typeof p.stills === 'string' && p.stills) bits.push(`stills: ${p.stills}${Array.isArray(p.reused) && p.reused.length ? ' (the other ' + p.reused.length + ' reused)' : ''}`);
    return bits.join(' · ');
  }
  /** The painter in a few letters for a card: "dev 32", "Klein", "dev 32 (reused)", "Klein (3 of 12 painted)". */
  function painterShort(p) {
    if (!p || typeof p !== 'object') return '';
    const s = (p.model === 'dev' ? 'dev' : 'Klein') + (p.steps ? ' ' + p.steps : '');
    if (p.stills === 'reused') return s + ' (stills reused)';
    return typeof p.stills === 'string' && p.stills ? `${s} (${p.stills})` : s;
  }
  /** The method a look was painted with: its recipe's `method`, else what the open document's words imply (Assets.methodOf). */
  function methodOf(look) {
    if (look.recipe && look.recipe.method) return String(look.recipe.method);
    if (current && current.doc && typeof Assets !== 'undefined' && typeof Assets.methodOf === 'function') { try { return Assets.methodOf(current.doc, look.code); } catch (_) { /* fall through */ } }
    return '';
  }
  /** The recipe's bookkeeping keys, written by the jobs and Duplicate… rather than typed: the painter it ran with, the
   *  method, the look a draft was made from, the look's own seed offset (pass 68). */
  const BOOK_KEYS = ['painter', 'method', 'from', 'seed_offset'];
  /** Where the game shows a hero look's own pictures (pass 68 review: the default Live title never shows a cut-out), said
   *  wherever the page offers or explains badge and cut-out candidates (here, jobs.js, assets.js). The badge:
   *  Registry.played_look / art_of (WHeroSheet, ResultsScreen, CollectionScreen, ArenaPanel); the cut-out: TitleScreen's
   *  painted branch only (Settings.menu_style, "live" by default; the switch is in Settings' debug panel). */
  const WHERE_SHOWN = {
    badge: 'the badge is what the hero sheet, the results, the Collection and the arena show for the look',
    cutout: 'the cut-out shows on the Painted title only (Settings, debug mode: Main menu → Painted); the Live title, the default, draws the look\'s strip instead',
  };
  /** The recipe's own keys apart from the bookkeeping ones. */
  function ownKeys(look) { return Object.keys(look.recipe && typeof look.recipe === 'object' ? look.recipe : {}).filter((k) => !BOOK_KEYS.includes(k)); }
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
    if (!states.has(k)) states.set(k, { filter: '', status: 'all', page: 0, selected: null, selectMode: false, checked: new Set(), confirm: null, edit: null, busy: false, players: new Map(), stage: null, jobSig: '' });
    return states.get(k);
  }
  /** What the cards and the stage show of one asset's jobs: its live (queued, running, waiting) jobs with a look code
   *  (the state chips, and which stubs are drafts). jobsChanged redraws only when this changed since the last render. */
  function jobsSig(kind, id) {
    const list = typeof Jobs !== 'undefined' && typeof Jobs.jobsFor === 'function' ? Jobs.jobsFor(kind, id) : [];
    return JSON.stringify(list.filter((j) => ['queued', 'running', 'waiting'].includes(j.state) && j.target && j.target.code).map((j) => [String(j.target.code), j.kind, j.state, j.id]).sort());
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
    s.jobSig = jobsSig(kind, id);   // the jobs this drawing shows (jobsChanged compares against it)
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
    const box = el('input', { type: 'search', class: 'txt lg-filter', placeholder: 'filter by code or note…', value: s.filter, title: 'show the looks whose code or note contains this' });
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
    const draft = isDraft(look, kind, id);
    if (isStub(look)) {
      // nothing painted: the server would serve the top-level strip in its place (sprite_path's fallback), so say so instead
      wrap.appendChild(el('div', { class: 'lg-stage-empty' }, el('b', { text: draft ? 'a draft: not painted yet' : 'not painted yet' }),
        el('span', { class: 'muted small', text: draft ? 'nothing runs until you press Generate…; change its recipe first in Recipe of ' + look.code + ' below (then Save asset)' : 'its look job is in the queue: see the Jobs tab' })));
    } else {
      const opts = playerOpts(kind, record, look, { mode: 'controls', zoom: 1 });
      if (s.stage && !s.stage.destroyed) { s.stage.setStrip(opts); }
      else s.stage = StripPlayer.create(opts);
      wrap.appendChild(s.stage.el);
    }
    const info = el('div', { class: 'lg-stage-info' });
    const chips = chipsFor(look, record, kind, id);
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
    const rec0 = look.recipe && typeof look.recipe === 'object' ? look.recipe : {};
    if (rec0.from) row('made from', `${rec0.from}${draft ? ' (Duplicate… copied its recipe; Generate… paints it)' : ''}`, 'the look this one was duplicated from (recipe.from)');
    if (look.base && !own.length) row('recipe', 'the base strip: the creature\'s own art words (the Art section) are its recipe' + (method ? ` · ${method}` : ''), 'the top-level strip has no recipe of its own');
    else if (!own.length) row('recipe', 'no recipe recorded' + (method ? ` · ${method} (implied)` : ''), 'painted before the Level Editor kept recipes, by hand, or by a job with an empty recipe: the creature\'s own words are what a job for this code would read now; Duplicate… starts a new look from them');
    else row('recipe', `${method || 'method implied'} · ${own.length} own key${own.length === 1 ? '' : 's'} (${own.slice(0, 6).join(', ')}${own.length > 6 ? ', …' : ''}); the rest inherited from the creature`, 'Recipe (typed)… shows every field with its source: own, inherited or the method\'s default');
    const w = wordsOf(look);
    if (w.text) row('words', (w.text.length > 150 ? w.text.slice(0, 150) + '…' : w.text) + (w.src === 'inherited' ? ' (the creature\'s own)' : ''), w.text);
    const painter = look.recipe && look.recipe.painter;
    row('painter', painter ? painterText(painter) + (isStub(look) ? ' (what Generate… starts from)' : '') : 'not recorded (painted before the painter was kept: Flux.2 Klein with its defaults unless the job said dev)', 'the model and the passes the stills were painted with (the job form\'s Model settings, kept in variants[CODE].recipe.painter); "stills reused" = they were on disk already, so this painter painted none of them');
    if (kind === 'hero' && !isStub(look)) {
      // pass 68 (D8, D9): a hero look's own round badge (variants[CODE].icon) and title cut-out (variants[CODE].title), else the hero's
      const ownCut = look.title_file;   // pass 70: a base made from a look keeps its own cut-out (the game reads the base entry's title)
      const cut = `/art/wanted/${encodeURIComponent(ownCut ? look.title_file : 'hero_' + id + '.png')}`;
      const thumbs = el('span', { class: 'lg-thumbs' },
        el('img', { src: `${look.icon || ''}${look.sprite_mtime ? '?v=' + encodeURIComponent(look.sprite_mtime) : ''}`, alt: '', title: (look.icon_file ? `its own badge: ${look.icon_file}` : 'the hero\'s badge (no badge of its own yet: Badge candidates…)') + ` · ${WHERE_SHOWN.badge}`, onerror: (e) => { e.target.remove(); } }),
        el('img', { src: cut, alt: '', title: (ownCut ? `its own title cut-out: ${look.title_file}` : `the hero's title cut-out (hero_${id}.png): Cut-out candidates… paints ${look.base ? 'it' : 'one of this look\'s own'}`) + ` · ${WHERE_SHOWN.cutout}`, onerror: (e) => { e.target.remove(); } }),
        el('span', { class: 'muted small', text: `${look.icon_file ? 'its own badge' : 'the hero\'s badge'} · ${ownCut ? 'its own cut-out' : 'the hero\'s cut-out'}` }));
      // where the game shows each one (pass 68 review: the cut-out never shows on the default Live title)
      const where = el('div', { class: 'muted small lg-where', text: `${WHERE_SHOWN.badge}; ${WHERE_SHOWN.cutout}.` });
      dl.appendChild(el('dt', { text: 'badge · cut-out', title: `the pictures the game shows for this look (a look without its own uses the hero's): ${WHERE_SHOWN.badge}; ${WHERE_SHOWN.cutout}` }));
      dl.appendChild(el('dd', {}, thumbs, where));
    }
    info.appendChild(dl);
    // pass 70: choose the look's badge / icon / cut-out from everything the finished jobs painted
    if (!isStub(look)) info.appendChild(pickers(kind, id, look));
    const acts = el('div', { class: 'lg-actions' });
    actions(acts, kind, id, record, look, s);
    info.appendChild(acts);
    wrap.appendChild(info);
    return wrap;
  }

  function chipsFor(look, record, kind, id) {
    const k = kind || (current && current.kind) || record.kind || 'enemy', cid = id || record.id;
    const out = [];
    if (isDefault(look, record)) out.push(el('span', { class: 'chip default', text: '● default', title: 'the look the game plays for every row that names none (the JSON\'s `variant`)' }));
    if (look.base) out.push(el('span', { class: 'chip base', text: 'base', title: 'the top-level strip of the JSON (variant_base)' }));
    if (look.fresh) out.push(el('span', { class: 'chip new', text: 'NEW', title: 'painted by a job and not yet approved: Approve clears the mark (the game ignores it)' }));
    if (look.shelved) out.push(el('span', { class: 'chip shelved', text: 'shelved', title: 'kept in the JSON but hidden from the arena chips and the default lists (variants[CODE].shelved); a row naming it still plays it' }));
    if (look.imported === false) out.push(el('span', { class: 'chip notimported', text: 'not imported', title: 'the strip\'s .import or the .tres is older than the files: the game plays the old data until an import runs' }));
    if (isDraft(look, k, cid)) out.push(el('span', { class: 'chip draft', text: 'draft', title: 'a look with a recipe and no painting: nothing runs until you press Generate… (a failed or cancelled job leaves one too); the game skips it' }));
    else if (isStub(look)) out.push(el('span', { class: 'chip stub', text: 'stub', title: 'no sprite yet: its look job is queued, running or waiting for a pick; the game skips it' }));
    for (const j of liveJobs(k, cid, look.code)) out.push(el('button', { type: 'button', class: 'chip state-' + j.state, text: (j.state === 'waiting' ? 'needs a pick' : j.state) + (j.kind !== 'look' ? ' · ' + ({ icon_cands: 'icons', hero_badge: 'badges', hero_title: 'cut-outs' }[j.kind] || j.kind) : ''), title: `${j.title || j.id}: open the Jobs tab`, onclick: (e) => { e.stopPropagation(); App.switchTab('jobs'); } }));
    return out;
  }

  function card(kind, id, record, look, s) {
    const draft = isDraft(look, kind, id);
    const c = el('article', { class: 'lg-card' + (look.code === s.selected ? ' selected' : '') + (look.shelved ? ' shelved' : '') + (isStub(look) ? ' stub' : '') + (draft ? ' draft' : ''), 'data-code': look.code });
    const top = el('div', { class: 'lg-card-top' }, el('b', { text: look.code }), ...chipsFor(look, record, kind, id));
    if (s.selectMode) {
      const cb = el('input', { type: 'checkbox', checked: s.checked.has(look.code), onclick: (e) => e.stopPropagation() });
      cb.addEventListener('change', () => { if (cb.checked) s.checked.add(look.code); else s.checked.delete(look.code); const n = s.checked.size; const bar = c.closest('.lookgrid').querySelector('.lg-bulk span'); if (bar) bar.textContent = `Selected ${n}:`; for (const b of c.closest('.lookgrid').querySelectorAll('.lg-bulk .btn:not(.ghost)')) b.disabled = !n; });
      top.appendChild(el('label', { class: 'cb' }, cb));
    }
    c.appendChild(top);
    const pic = el('div', { class: 'lg-pic' });
    if (isStub(look)) pic.appendChild(el('div', { class: 'placeholder', text: draft ? `draft${look.recipe && look.recipe.from ? ' from ' + look.recipe.from : ''}: not painted yet` : 'no sprite yet' }));
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
    c.appendChild(el('div', { class: 'lg-meta', text: `${method || '?'} · ${meta}${painter ? ' · ' + painterShort(painter) : ''}`,
      title: `${method ? 'method ' + method : 'the method is not recorded'} · ${meta}${painter ? (draft ? ' · Generate… starts from ' : ' · painted with ') + painterText(painter) : ' · the painter was not recorded'}` }));
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
    const stub = isStub(look), draft = isDraft(look, kind, id);
    const b = (text, title, fn, cls) => host.appendChild(el('button', { type: 'button', class: 'btn small' + (cls === 'primary' ? '' : ' ghost') + (cls ? ' ' + cls : ''), text, title, disabled: s.busy, onclick: (e) => { e.stopPropagation(); fn(); } }));
    // a draft is painted only when you say so (pass 68, D5)
    if (draft) b('Generate…', `paint ${look.code}: the job form opens for this code as a new look, with its recipe, its method and its painter (the document is saved first: the job reads the recipe from the file); the look's candidates come with it`, () => generate(kind, id, look.code), 'primary');
    if (!def) {
      if (look.ready !== false && !look.shelved) b('Make default', `write "variant": "${look.code}" in ${id}.json (after a backup) and import it: every row that names no look plays it`, () => op(kind, id, record, s, look.code, { op: 'default' }));
    }
    if (look.fresh) b('Approve', 'you looked at it and it stays: clears the NEW mark (deletes variants[CODE].fresh; the game never read it)', () => op(kind, id, record, s, look.code, { op: 'approve' }));
    if (!look.shelved) {
      if (def) host.appendChild(el('span', { class: 'muted', text: 'Shelve', title: 'the look in play cannot be shelved: make another the default first' }));
      else if (!stub) b('Shelve', 'keep it, but hide it from the arena chips and the default lists (variants[CODE].shelved = true)', () => op(kind, id, record, s, look.code, { op: 'shelve' }));
    } else b('Unshelve', 'show it in the arena and the lists again', () => op(kind, id, record, s, look.code, { op: 'unshelve' }));
    if (def) host.appendChild(el('span', { class: 'muted', text: 'Remove', title: 'the look in play cannot be removed: make another the default first' }));
    else if (look.base) b('Remove…', 'remove the base look (pass 70): you choose which look becomes the base; its strip, icon, anims and fps become the JSON\'s top-level art, the base\'s own files move to tools/level_editor/backups/deleted/<id>/<stamp>/, then an import runs', () => { s.confirm = { codes: [look.code], base: true, newBase: baseChoices(record, look)[0] || '' }; redraw(); }, 'danger');
    else b('Remove', 'delete the entry; its PNGs and .import files move to tools/level_editor/backups/deleted/<id>/<stamp>/ (refused while a map row names it)', () => { s.confirm = { codes: [look.code] }; redraw(); }, 'danger');
    b('Edit note / recipe', 'the note shown on the cards and the recipe the art job reads (raw JSON)', () => { s.edit = { code: look.code, note: look.note || '', recipe: look.recipe || null }; redraw(); });
    if (current && current.doc && typeof Assets !== 'undefined' && typeof Assets.recipeEditor === 'function') b('Recipe (typed)…', 'select it and go to its recipe as typed fields per method (under the grid): Save asset keeps the changes', () => showRecipe(look.code, look));
    if (!stub) b('Re-roll…', 'queue the look again: the job form opens with its recipe and painter; choose what to throw away (new seeds, redo the clips, repaint the stills; one view for gen_ctl)', () => openForm(kind, id, { mode: 'look', code: look.code, method: methodOf(look) || undefined, recipe: look.recipe || null, painter: (look.recipe && look.recipe.painter) || null, reroll: true }));
    b('Duplicate…', 'a draft copy of this look under the next free code: its recipe, words and painter copied; nothing is painted until you press Generate… on the draft (change its recipe first if you like)', () => duplicateDraft(kind, id, record, s, look));
    if (!draft) {
      // a look's own icon (pass 68, D8): a hero's icon is the round badge, so a hero look offers badge and title cut-out
      // candidates; the base look's go to the hero's (or the creature's) own files
      const code = look.base ? undefined : look.code;
      const whose = code ? `${look.code}'s own` : 'the base look\'s (the top-level files)';
      if (kind === 'hero') {
        b('Badge candidates…', `paint round badge candidates for ${whose} icon: the hero's words and this look's front still as the reference, all editable in the form. ${cap(WHERE_SHOWN.badge)}`, () => openForm(kind, id, { mode: 'badge', method: 'hero_badge', code }));
        b('Cut-out candidates…', `paint title cut-out candidates for ${whose} cut-out (660 × 888): the hero's words, the title pose and this look's front still. ${cap(WHERE_SHOWN.cutout)}`, () => openForm(kind, id, { mode: 'title', method: 'hero_title', code }));
      } else b('Icon candidates…', `paint icon candidates for ${whose} icon to pick from: the creature's words and this look's front still as the reference`, () => openForm(kind, id, { mode: 'icon', method: 'icon_cands', code }));
    }
  }

  /** Select a look and bring its typed recipe editor (under the grid, the editor pane's own) into view. */
  function showRecipe(code, look) {
    if (!current) return;
    st(current.kind, current.id).selected = code;
    if (current.opts && typeof current.opts.onSelect === 'function') current.opts.onSelect(code, look);
    else redraw();
    setTimeout(() => { const r = document.querySelector('.aeditor .recipe'); if (r) r.scrollIntoView({ block: 'start', behavior: 'smooth' }); }, 80);
  }

  /** The source recipe of a look: the open document's entry (saved first, so it is what the file holds), else the record's. */
  function recipeOf(code, look) {
    const d = current && current.doc && current.doc.data;
    const e = d && d.variants && typeof d.variants === 'object' && d.variants[code] && typeof d.variants[code] === 'object' ? d.variants[code] : null;
    if (e) return e.recipe && typeof e.recipe === 'object' ? e.recipe : {};
    return look && look.recipe && typeof look.recipe === 'object' ? look.recipe : {};
  }

  /** Duplicate… (pass 68, D5): a DRAFT, nothing painted. POST /api/content/<kind>/<id>/look {note, recipe} (the server's
   *  add_look: the next free code, an entry without a sprite, no job). The draft's recipe is the source's, `method` set
   *  (so it never drifts to an implied one), the painter kept (Generate…'s Model settings start from it), `stills` and
   *  `seed_offset` left out (the draft gets paintings and seeds of its own when it is generated), `from` = the source. */
  async function duplicateDraft(kind, id, record, s, look) {
    const doc = current && current.kind === kind && current.id === id ? current.doc : null;
    if (doc && typeof Assets !== 'undefined' && typeof Assets.ensureSaved === 'function' && !(await Assets.ensureSaved(doc, `Duplicate… copies ${look.code}'s recipe from the file.`))) return;
    const recipe = JSON.parse(JSON.stringify(recipeOf(look.code, look)));
    const method = methodOf(look);
    if (method) recipe.method = method;
    delete recipe.stills;
    delete recipe.seed_offset;
    recipe.from = look.code;
    const note = (look.note ? look.note + ' · ' : '') + 'from ' + look.code;
    s.busy = true;
    redraw();
    App.status(`${record.name || id}: a draft from ${look.code}…`, 'busy');
    const res = await post(`/api/content/${encodeURIComponent(kind)}/${encodeURIComponent(id)}/look`, { note, recipe });
    s.busy = false;
    if (!res || !res.ok) { App.status(`${id}: no draft from ${look.code}: ${(res && res.error) || 'no answer'}`, 'bad'); redraw(); return; }
    s.selected = res.code;
    s.filter = '';
    s.status = 'all';
    if (doc && doc.ui) doc.ui.look = res.code;
    App.status(`${res.code} is a draft of ${look.code}: nothing is painted yet. Change its recipe below (Recipe of ${res.code}), Save asset, then press Generate… on its card`, 'good');
    await refresh(kind, id, record, s, res.looks);
    showRecipe(res.code);
  }

  /** Generate… on a draft (D5): the document saved first (the job reads the recipe from the JSON and writes it again),
   *  a look job of its own refused, then the job form for this code as a NEW look: its recipe, method and painter, and
   *  the box that reuses the paintings of the look it was made from. */
  async function generate(kind, id, code) {
    const doc = current && current.kind === kind && current.id === id ? current.doc : null;
    if (doc && typeof Assets !== 'undefined' && typeof Assets.ensureSaved === 'function' && !(await Assets.ensureSaved(doc, `Generate… paints ${code} from its recipe in the file.`))) return;
    if (typeof Jobs !== 'undefined' && typeof Jobs.poll === 'function') { try { await Jobs.poll(); } catch (_) { /* the list as it was */ } }
    if (liveJobs(kind, id, code, true).length) { App.status(`${code} has a look job in the queue already: see the Jobs tab`, 'bad'); redraw(); return; }
    const rec = current && current.kind === kind && current.id === id ? current.record : null;
    const look = rec ? looksOf(rec).find((l) => l.code === code) : null;
    const recipe = JSON.parse(JSON.stringify(recipeOf(code, look)));
    openForm(kind, id, { mode: 'look', code, draft: true, method: recipe.method || (look ? methodOf(look) : '') || undefined, recipe, painter: recipe.painter || null, from: recipe.from || null, note: look ? look.note || '' : '' });
  }

  /** The job list changed which looks have live jobs (Jobs.applyList, for any asset): the chips and the draft buttons
   *  follow, but only when the jobs of the asset on screen changed (jobsSig), and never while the edit or the confirm box
   *  is open over the grid (the note and recipe being typed stay; closing the box draws the grid again with the jobs as
   *  they are then). The filter box keeps its focus and caret through the redraw. True when the grid was drawn again. */
  function jobsChanged() {
    if (!current || !current.container || !current.container.isConnected) return false;
    const s = st(current.kind, current.id);
    if (s.edit || s.confirm) return false;
    if (jobsSig(current.kind, current.id) === s.jobSig) return false;
    const ae = typeof document !== 'undefined' ? document.activeElement : null;
    const typing = ae && ae.classList && ae.classList.contains('lg-filter') && current.container.contains(ae) ? [ae.selectionStart, ae.selectionEnd] : null;
    render(current.container, current.record, current.doc, current.opts);
    const box = typing ? current.container.querySelector('input.lg-filter') : null;
    if (box) { box.focus(); try { box.setSelectionRange(typing[0], typing[1]); } catch (_) { /* no caret to put back */ } }
    return true;
  }

  /** The looks that may become the base when `base` goes (pass 70, server.base_choices): a look with a strip of its own
   *  (not a stub or a draft, not the base), the one in play first. */
  function baseChoices(record, base) {
    const play = playCode(record);
    return looksOf(record).filter((l) => l.code !== base.code && !l.base && !isStub(l) && l.ready !== false && l.sprite_file)
      .map((l) => l.code).sort((a, b) => ((a !== play) - (b !== play)) || String(a).localeCompare(String(b), undefined, { numeric: true }));
  }

  /** Removing the base look (pass 70): which look becomes the base, what moves where, Yes / Cancel. */
  function baseConfirm(kind, id, record, s) {
    const code = s.confirm.codes[0];
    const choices = baseChoices(record, { code });
    const box = el('div', { class: 'lg-confirm lg-rebase' });
    if (!choices.length) {
      box.appendChild(el('span', { text: `${code} is ${record.name || id}'s base look. No other look has a strip of its own yet, so none can become the base: paint one first (+ New look…), then remove ${code}.` }));
      box.appendChild(el('button', { type: 'button', class: 'btn small ghost', text: 'Close', onclick: () => { s.confirm = null; redraw(); } }));
      return box;
    }
    if (!choices.includes(s.confirm.newBase)) s.confirm.newBase = choices[0];
    const sel = el('select', { class: 'lg-newbase', title: 'the look whose strip, icon, anims and fps become the top-level art (the base)' });
    for (const c of choices) sel.appendChild(el('option', { value: c, text: c + (c === playCode(record) ? ' (in play)' : ''), selected: c === s.confirm.newBase }));
    sel.addEventListener('change', () => { s.confirm.newBase = sel.value; });
    box.appendChild(el('span', { text: `Remove ${code}, ${record.name || id}'s base look? Which look becomes the base:` }));
    box.appendChild(sel);
    box.appendChild(el('span', { class: 'muted small', text: `The new base's strip, icon, anims and fps become ${id}.json's top-level art (no file is renamed; its entry, recipe and cut-out stay, so its re-rolls still use its own recipe), variant_base names it, ${code}'s entry goes, and ${code}'s own files (the old top-level strip and icon, nothing else names them) move to tools/level_editor/backups/deleted/${id}/<stamp>/ with base_${code}.json (what it was); a backup of the JSON first, then an import. Looks that inherited the old top-level anims or fps get them written into their own entries, so they play as before.` }));
    box.appendChild(el('button', { type: 'button', class: 'btn small danger', text: s.busy ? 'Removing…' : `Yes, remove ${code}`, disabled: s.busy, onclick: () => { const nb = sel.value; s.confirm = null; op(kind, id, record, s, code, { op: 'remove', new_base: nb }); } }));
    box.appendChild(el('button', { type: 'button', class: 'btn small ghost', text: 'Cancel', onclick: () => { s.confirm = null; redraw(); } }));
    return box;
  }

  function confirmBox(kind, id, record, s) {
    if (s.confirm.base) return baseConfirm(kind, id, record, s);
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
    // what is typed is kept on s.edit as drafts (noteDraft, recipeText), apart from the note and recipe Save compares
    // with, so a redraw of the grid while the box is open (this asset's job landing) does not wipe it
    const note = el('input', { type: 'text', class: 'txt wide', value: e.noteDraft != null ? e.noteDraft : e.note, placeholder: 'what this look is, in a line (shown on the cards and the arena chips)' });
    note.addEventListener('input', () => { e.noteDraft = note.value; });
    box.appendChild(el('div', { class: 'row' }, el('span', { class: 'muted small', text: 'note' }), note));
    const ta = el('textarea', { class: 'mono', spellcheck: false, placeholder: '{ "method": "creature_pose2", "pose": "walk_zombie", ... }  (the keys the art job reads; empty = none)' });
    ta.value = e.recipeText != null ? e.recipeText : (e.recipe ? JSON.stringify(e.recipe, null, 2) : '');
    const err = el('span', { class: 'warn-text small' });
    const validate = () => { try { if (ta.value.trim()) JSON.parse(ta.value); err.textContent = ''; } catch (x) { err.textContent = 'not JSON: ' + x.message; } };
    ta.addEventListener('input', () => { e.recipeText = ta.value; validate(); });
    if (e.recipeText != null) validate();
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

  // ------------------------------------------------------------------ pass 70: choose a look's badge, icon or cut-out

  /** The job kinds whose candidates a picker lists: a hero's badge (hero_badge, raw portraits the install turns into the
   *  round badge), a hero's title cut-out (hero_title, finished cut-outs), a creature's icon (icon_cands). */
  const PICK_KINDS = { badge: ['hero_badge'], title: ['hero_title'], icon: ['icon_cands'] };
  const PICK_NOUN = { badge: 'badge', title: 'title cut-out', icon: 'icon' };
  /** Every finished candidate job of an asset for `what`, newest first (the Jobs tab's list: Jobs.jobsFor). Garry, pass 70:
   *  "I should be able to choose any icon that was saved from the jobs that were done". */
  function paintedCandidates(kind, id, what) {
    const list = typeof Jobs !== 'undefined' && typeof Jobs.jobsFor === 'function' ? Jobs.jobsFor(kind, id) : [];
    return list.filter((j) => (PICK_KINDS[what] || []).includes(j.kind) && j.state === 'done' && Array.isArray(j.choices) && j.choices.length)
      .sort((a, b) => String(b.ended || b.created || '').localeCompare(String(a.ended || a.created || '')));
  }
  const pickOpen = new Set();   // `${kind}|${id}|${code}|${what}`: the pickers left open (they survive the redraws)

  /** A picker: every candidate `what` any finished job painted for this asset, grouped by job (newest first, the look it
   *  was painted for named), one click to choose, Install to write it as `code`'s own (code '' = the asset's own, the
   *  base look's top-level files). Install queues an install job (POST /api/jobs/<job>/install {choice, options:
   *  {variant: code}}): the badge made from the portrait, or the icon finished, or the cut-out copied, the old file backed
   *  up, the look's entry naming it, then an import. */
  function picker(kind, id, o) {
    const what = o.what;
    const code = o.code || '';
    const forWhom = o.label || (code ? `${code}'s` : 'the base look\'s');
    const noun = PICK_NOUN[what] || what;
    const jobs = paintedCandidates(kind, id, what);
    const n = jobs.reduce((a, j) => a + j.choices.length, 0);
    const okey = `${kind}|${id}|${code}|${what}`;
    const det = el('details', { class: 'lg-picker', 'data-what': what, 'data-code': code });
    if (pickOpen.has(okey)) det.open = true;
    det.addEventListener('toggle', () => { if (det.open) pickOpen.add(okey); else pickOpen.delete(okey); });
    det.addEventListener('click', (e) => e.stopPropagation());
    det.appendChild(el('summary', { text: `Choose ${forWhom} ${noun} from everything painted (${n} in ${jobs.length} job${jobs.length === 1 ? '' : 's'})`,
      title: `every ${noun} candidate a finished job made for ${id} (any look); Install writes the one you choose as ${forWhom} ${noun}` }));
    if (!n) {
      det.appendChild(el('div', { class: 'muted small', text: `No finished ${noun} candidates for ${id} yet: ${what === 'title' ? 'Cut-out candidates…' : what === 'badge' ? 'Badge candidates…' : 'Icon candidates…'} paints some (the job lists them here when it is done).` }));
      return det;
    }
    let picked = null;
    const msg = el('span', { class: 'muted small' });
    const btn = el('button', { type: 'button', class: 'btn small primary', text: `Install as ${forWhom} ${noun}`, disabled: true, title: 'queues an install job: the old file is backed up, the look\'s entry names the new one, then an import' });
    btn.addEventListener('click', async (e) => {
      e.stopPropagation();
      if (!picked) return;
      btn.disabled = true;
      msg.textContent = 'queuing…';
      const res = await post(`/api/jobs/${encodeURIComponent(picked.job.id)}/install`, { choice: picked.choice, options: { variant: code } });
      if (!res || !res.ok) { msg.textContent = `refused: ${(res && res.error) || 'no answer'}`; btn.disabled = false; return; }
      msg.textContent = `queued ${res.job && res.job.id ? '#' + String(res.job.id).slice(-4) : 'an install job'}: ${picked.label} becomes ${forWhom} ${noun}, then an import (see the Jobs tab)`;
      if (typeof App !== 'undefined') App.status(`${id}: installing ${picked.label} of #${String(picked.job.id).slice(-4)} as ${forWhom} ${noun}`, 'good');
      if (typeof Jobs !== 'undefined' && typeof Jobs.poll === 'function') { try { await Jobs.poll(); } catch (_) { /* the list as it was */ } }
    });
    for (const j of jobs) {
      const grp = el('div', { class: 'lg-pick-group' });
      const when = String(j.ended || j.created || '').replace('T', ' ').slice(0, 16);
      grp.appendChild(el('div', { class: 'muted small', text: `#${String(j.id).slice(-4)} · painted for ${j.target && j.target.code ? j.target.code : 'the base'} · ${when}${j.spec && j.spec.model === 'dev' ? ' · Flux.2 dev' : ''}`, title: j.title || j.id }));
      const grid = el('div', { class: 'lg-pick-grid' + (what === 'badge' ? ' round' : '') + (what === 'title' ? ' tall' : '') });
      for (const ch of j.choices) {
        const tile = el('button', { type: 'button', class: 'lg-pick', title: `${ch.label || ch.id} of ${j.title || j.id}` },
          el('img', { src: ch.url, alt: '', loading: 'lazy' }), el('span', { class: 'small', text: ch.label || String(ch.id) }));
        tile.addEventListener('click', (e) => {
          e.stopPropagation();
          picked = { job: j, choice: String(ch.id), label: ch.label || String(ch.id) };
          for (const t of det.querySelectorAll('.lg-pick')) t.classList.toggle('picked', t === tile);
          btn.disabled = false;
          btn.textContent = `Install ${picked.label} (#${String(j.id).slice(-4)}) as ${forWhom} ${noun}`;
          msg.textContent = '';
        });
        grid.appendChild(tile);
      }
      grp.appendChild(grid);
      det.appendChild(grp);
    }
    det.appendChild(el('div', { class: 'lg-pick-actions' }, btn, msg));
    return det;
  }

  /** The pickers a look offers: a hero look its badge and its title cut-out, a creature look its icon. */
  function pickers(kind, id, look) {
    const code = look.base ? '' : look.code;
    const label = look.base ? `${look.code}'s (the base look's)` : `${look.code}'s`;
    const wrap = el('div', { class: 'lg-pickers' });
    if (kind === 'hero') {
      wrap.appendChild(picker(kind, id, { what: 'badge', code, label }));
      wrap.appendChild(picker(kind, id, { what: 'title', code, label }));
    } else wrap.appendChild(picker(kind, id, { what: 'icon', code, label }));
    return wrap;
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

  return { painterText, painterShort, ownKeys, isStub, isDraft, BOOK_KEYS, WHERE_SHOWN, render, select, dispose, playerOpts, looksOf, generate, jobsChanged, PAGE, STATUS,
    picker, pickers, paintedCandidates, PICK_KINDS, baseChoices };   // pass 70
})();
if (typeof module !== 'undefined') module.exports = LookGrid;
