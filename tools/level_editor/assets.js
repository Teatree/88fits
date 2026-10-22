'use strict';
// Pass 66 (lane P): the asset editors' documents and what every editor shares. One document per open enemy / boss, hero
// or item (`Assets.S.docs`, keyed kind:id) with its own history (300 steps, Assets.apply mirrors App.apply), dirty state
// and Save (`POST /api/content/<kind>/<id>/save {json, base_mtime}`; a 409 when the file changed on disk offers Reload /
// Keep mine / Show the other). app.js asks `Assets.owns(S.tab)` and `Assets.hasDoc(S.tab)` before treating Save, Undo,
// Redo, Revert and the top bar as the map's. Also here: the lists the editors read (/api/heroes, /api/items, /api/vocab,
// /api/methods, /api/drivers, a map's timeline for the compare panel), the field renderer for the asset types that
// forms.js does not know (stat effects, level steps, anims, sound ids, JSON boxes with key chips, id pickers, drivers,
// checklists, tags, power-up weights), the sticky header, the issues line, the sections, the create dialog, Test in game,
// the per-look recipe editor and "Show the words that will be sent".
const Assets = (() => {
  const { el, clear, fmtN } = U;
  const M = AssetsModel, F = AFIELDS;
  const HISTORY_MAX = 300;
  // pass 69 (lane LE): a hero's perk is a document of the Heroes tab
  const KIND_TAB = { enemy: 'creatures', boss: 'creatures', hero: 'heroes', weapon: 'items', evolution: 'items', passive: 'items', mutation: 'items', perk: 'heroes' };
  const KIND_LABEL = { enemy: 'ENEMY', boss: 'BOSS', hero: 'HERO', weapon: 'WEAPON', evolution: 'EVOLUTION', passive: 'PASSIVE', mutation: 'MUTATION', perk: 'PERK' };
  const KIND_ICON = { enemy: 'enemy', boss: 'boss', hero: 'hero', weapon: 'weapon', evolution: 'evolution', passive: 'passive', mutation: 'mutation', perk: 'perk' };

  const S = {
    lists: { heroes: null, items: null },      // the server's records (/api/heroes, /api/items); `enemies` mirrors App.S.enemies (a getter below)
    open: { creatures: null, heroes: null, items: null },   // the document shown on each tab (a docs key)
    docs: {},
    vocab: null, methods: null, drivers: null,
    maps: {},                                   // map id -> timeline_data (the compare panel's own choice)
    loading: {}, failed: {},
    filters: { heroes: { q: '', status: 'all' }, items: { q: '', kind: 'all', status: 'all' } },
  };

  Object.defineProperty(S.lists, 'enemies', { get: () => (typeof App !== 'undefined' ? App.S.enemies : []), enumerable: true });

  // ------------------------------------------------------------------ fetch

  async function getJSON(url) {
    const r = await fetch(url, { cache: 'no-store' });
    if (!r.ok) throw new Error(`${url}: HTTP ${r.status}`);
    return r.json();
  }
  /** POST JSON; returns {status, data} (data = the parsed body, or {ok: false, error} when it was not JSON). */
  async function postJSON(url, body) {
    const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) });
    let data;
    try { data = await r.json(); } catch (_) { data = { ok: false, error: `HTTP ${r.status}` }; }
    return { status: r.status, data };
  }

  /** Load one list once; the tab draws again when it lands. A route that is not there yet (lane S) is remembered in
   *  S.failed so the page says so instead of crashing. */
  function load(name, url, into) {
    if (S.loading[name] || (into() != null) || S.failed[name]) return false;
    S.loading[name] = true;
    getJSON(url).then((data) => { S.loading[name] = false; S.failed[name] = null; setList(name, data); App.render('tab'); })
      .catch((e) => { S.loading[name] = false; S.failed[name] = e.message; App.render('tab'); });
    return true;
  }
  function setList(name, data) {
    if (name === 'heroes') S.lists.heroes = Array.isArray(data) ? data : (data && data.heroes) || [];
    else if (name === 'items') S.lists.items = data || {};
    else if (name === 'vocab') S.vocab = data || {};
    else if (name === 'methods') S.methods = data || {};
    else if (name === 'drivers') S.drivers = Array.isArray(data) ? data : (data && data.drivers) || [];
  }
  const ensureHeroes = () => load('heroes', '/api/heroes', () => S.lists.heroes);
  const ensureItems = () => load('items', '/api/items', () => S.lists.items);
  const ensureVocab = () => load('vocab', '/api/vocab', () => S.vocab);
  const ensureMethods = () => {
    if (S.methods != null || S.loading.methods) return false;
    S.loading.methods = true;
    // lane S's route, else the file itself (server.py serves the editor folder's flat .json files)
    getJSON('/api/methods').catch(() => getJSON('/methods.json')).then((data) => { S.loading.methods = false; setList('methods', data); App.render('tab'); })
      .catch((e) => { S.loading.methods = false; S.failed.methods = e.message; S.methods = {}; App.render('tab'); });
    return true;
  };
  const ensureDrivers = () => load('drivers', '/api/drivers', () => S.drivers);
  async function refreshList(name) {
    try {
      if (name === 'heroes') setList('heroes', await getJSON('/api/heroes'));
      else if (name === 'items') setList('items', await getJSON('/api/items'));
      else if (name === 'enemies') await App.refreshCreatures();
    } catch (e) { App.status(`Could not read /api/${name}: ${e.message}`, 'bad'); }
  }
  /** A map's timeline for the compare panel (default red_canyon; App.tl() when that map is the open one). */
  function mapTl(id) {
    const mid = id || 'red_canyon';
    if (App.S.map && App.S.mapId === mid) return App.tl();
    if (S.maps[mid]) return S.maps[mid];
    if (!S.loading['map:' + mid]) {
      S.loading['map:' + mid] = true;
      getJSON('/api/map/' + mid).then((m) => { S.maps[mid] = (m && m.timeline_data) || {}; S.loading['map:' + mid] = false; App.render('tab'); })
        .catch(() => { S.maps[mid] = {}; S.loading['map:' + mid] = false; });
    }
    return null;
  }

  /** The vocabulary: the server's over the built-in defaults (the lists are the game's constants either way). */
  // lane S's names for the lists this page calls otherwise (its vocab.py: behaviours, mutation_kinds, quest_types, shot_kinds, ...)
  const VOCAB_ALIAS = { behaviours: 'behaviors', mutation_kinds: 'mutationKinds', shot_kinds: 'shotKinds', quest_types: 'questTypes', rarity_plate: 'rarityPlate', favourite_bonus_types: 'favouriteBonus', favourite_passive_bonus_types: 'passiveBonus', placeholder_shapes: 'placeholderShapes' };
  function vocab() {
    const v = Object.assign({}, F.VOCAB);
    const sv = S.vocab || {};
    for (const key of Object.keys(sv)) {
      const val = sv[key];
      const mine = VOCAB_ALIAS[key] || key;
      if (Array.isArray(val) && val.length && (typeof val[0] === 'string' || typeof val[0] === 'number')) {
        // the server's list in its order, my help texts kept where the value matches, my values the server lacks appended
        const defaults = Array.isArray(F.VOCAB[mine]) ? F.VOCAB[mine] : [];
        const byV = {};
        for (const o of defaults) if (M.isObj(o)) byV[String(o.v)] = o;
        const out = val.map((x) => byV[String(x)] || { v: x, label: String(x) });
        for (const o of defaults) if (M.isObj(o) && !val.some((x) => String(x) === String(o.v))) out.push(o);
        v[mine] = out;
      } else if (val != null && !(mine === 'rarityPlate' && M.isObj(val))) {
        // a dict where the page keeps an option list (quest_types: type -> its keys; attacks, blocks) stays under the server's own name
        if (Array.isArray(F.VOCAB[mine]) && !Array.isArray(val)) v[key] = val; else v[mine] = val;
      }
      if (mine === 'rarityPlate' && M.isObj(val)) { v.rarityPlate = {}; for (const r of Object.keys(val)) v.rarityPlate[r] = String(val[r]).startsWith('#') ? val[r] : '#' + val[r]; }
    }
    // the sound ids as one plain list (the server groups them by prefix)
    if (Array.isArray(sv.sounds)) v.sounds = sv.sounds.map((x) => (typeof x === 'string' ? x : x.v || x.id));
    else if (sv.sounds && typeof sv.sounds === 'object') v.sounds = Array.from(new Set(Object.values(sv.sounds).flat().map((x) => (typeof x === 'string' ? x : x.id || x.v)))).sort();
    // the stats: TextGen's names (stat_names: stat -> [name, kind]) and the two sets as lists of ids
    if (sv.stat_names && M.isObj(sv.stat_names)) { v.stats = {}; for (const st of Object.keys(sv.stat_names)) { const e = sv.stat_names[st]; v.stats[st] = Array.isArray(e) ? { name: e[0], kind: e[1] } : (M.isObj(e) ? e : { name: String(e), kind: 'num' }); } }
    else if (sv.stats && M.isObj(sv.stats)) v.stats = sv.stats;
    for (const k2 of ['player_stats', 'weapon_stats']) {
      const val = sv[k2];
      if (M.isObj(val)) v[k2] = Object.keys(val).concat(Array.isArray(sv[k2 + '_extra']) ? sv[k2 + '_extra'] : []);
      else if (Array.isArray(val)) v[k2] = val.map((x) => (typeof x === 'string' ? x : x.v || x.id));
    }
    if (sv.combos_seen) v.combos_seen = sv.combos_seen;
    return v;
  }

  /** The items lists in one flat shape {weapons, evolutions, mutations, passives, quests} from /api/items' grouped one. */
  function flatItems() {
    const it = S.lists.items;
    if (!it) return null;
    const seen = {};
    const PATH_KINDS = ['element', 'volume', 'motion', 'stance', 'hero'];
    // lane S's records carry the content kind in `kind` ("mutation"); a mutation's own kind (element / volume / motion) is `mutation_kind`
    const norm = (list, x) => (list === 'mutations' && !PATH_KINDS.includes(String(x.kind)) ? Object.assign({}, x, { kind: PATH_KINDS.includes(String(x.mutation_kind)) ? x.mutation_kind : (x.hero ? 'hero' : 'motion') }) : x);
    const add = (list, x, extra) => { if (!x || !x.id || seen[list + ':' + x.id]) return; seen[list + ':' + x.id] = true; out[list].push(norm(list, extra ? Object.assign({}, x, extra) : x)); };
    const out = { weapons: [], evolutions: [], mutations: [], passives: [], quests: [] };
    for (const w of it.weapons || []) {
      add('weapons', w);
      if (w.evolution) add('evolutions', w.evolution, { is_evolution: true, evolved_from: w.evolution.evolved_from || w.id });
      for (const m of w.mutations || []) add('mutations', m);
    }
    for (const e of it.evolutions || []) add('evolutions', e, { is_evolution: true });
    for (const m of it.mutations || []) add('mutations', m);
    for (const l of it.lines || []) { add('passives', l); if (l.evolved) add('passives', l.evolved); }
    for (const p of it.passives || []) add('passives', p);
    for (const q of it.quests || []) add('quests', q);
    return out;
  }
  const lists = () => ({ enemies: App.S.enemies, heroes: S.lists.heroes, items: flatItems() });
  function listRecord(doc) {
    if (doc.kind === 'enemy' || doc.kind === 'boss') return App.creature(doc.id);
    if (doc.kind === 'hero') return (S.lists.heroes || []).find((h) => h.id === doc.id) || null;
    const fl = flatItems();
    if (!fl) return null;
    const list = doc.kind === 'weapon' ? fl.weapons : doc.kind === 'evolution' ? fl.evolutions : doc.kind === 'passive' ? fl.passives : fl.mutations;
    return list.find((x) => x.id === doc.id) || null;
  }
  function seenCombos(doc) {
    if (doc.combos) return new Set(doc.combos);
    const v = vocab();
    if (Array.isArray(v.combos_seen)) return new Set(v.combos_seen);
    // from the palette's records: brain + the blocks the record carries
    const out = new Set();
    for (const c of App.S.enemies || []) {
      const blocks = ['ranged', 'charge', 'kamikaze', 'artillery', 'boss', 'elite'].filter((b) => c[b]);
      out.add(`${c.brain || 'chase'}|${blocks.sort().join('+')}`);
    }
    return out;
  }

  // ------------------------------------------------------------------ documents

  const key = (kind, id) => `${kind}:${id}`;
  const tabOf = (kind) => KIND_TAB[kind] || 'items';
  /** The tabs whose Save / Undo / top bar are a document's: heroes, items and jobs always; the Enemies tab (id
   *  `creatures`) while an enemy document is open. */
  function owns(tab) { return tab === 'heroes' || tab === 'items' || tab === 'jobs' || (tab === 'creatures' && !!S.open.creatures); }
  function hasDoc(tab) { const k = S.open[tab || App.S.tab]; return !!(k && S.docs[k]); }
  function active(tab) { const k = S.open[tab || App.S.tab]; return k && S.docs[k] ? S.docs[k] : null; }
  function docsOf(tab) { return Object.values(S.docs).filter((d) => tabOf(d.kind) === tab); }
  const docDirty = (doc) => !!doc && JSON.stringify(doc.data) !== doc.saved;
  function dirty(tab) { return docDirty(active(tab)); }
  function anyDirty() { return Object.values(S.docs).some(docDirty); }

  /** Open a document (GET /api/content/<kind>/<id>) on its tab; an open one is shown again (its edits kept). */
  async function open(kind, id, opts) {
    const o = opts || {};
    const k = key(kind, id), tab = tabOf(kind);
    if (S.docs[k] && !o.reload) { S.open[tab] = k; show(tab); return S.docs[k]; }
    App.status(`Loading ${id}…`, 'busy');
    let rec;
    try {
      const r = await fetch(`/api/content/${encodeURIComponent(kind)}/${encodeURIComponent(id)}`, { cache: 'no-store' });
      if (r.status === 404) throw new Error('the server has no /api/content route yet (lane S)');
      rec = await r.json();
      if (!rec.ok) throw new Error(rec.error || `HTTP ${r.status}`);
    } catch (e) {
      App.status(`Could not open ${kind} ${id}: ${e.message}`, 'bad');
      return null;
    }
    const data = rec.json || {};
    const old = S.docs[k];
    const doc = {
      key: k, kind: rec.kind || kind, id, file: rec.file || '', text: rec.text || '', data, saved: JSON.stringify(data),
      history: [], future: [], saving: false, baseMtime: rec.mtime, looks: rec.looks || [], refs: rec.refs || {}, files: rec.files || null,
      combos: rec.combos_seen || null, deletable: rec.deletable, editable: rec.editable, layout: rec.layout, quest: rec.quest || null, pathMissing: rec.path_missing || null,
      templateId: o.templateId || (old && old.templateId) || null, badJson: {},
      ui: old ? old.ui : { open: {}, look: null, map: 'red_canyon', compareWith: null, jsonText: {}, drawer: null },
    };
    S.docs[k] = doc;
    S.open[tab] = k;
    App.status(`Opened ${doc.file || id}`);
    show(tab);
    return doc;
  }
  function show(tab) { if (App.S.tab !== tab) App.switchTab(tab); else App.render('tab'); }

  /** Close a document (asks when it has unsaved changes); the tab shows another open one, else its list alone. */
  function close(k) {
    const doc = S.docs[k];
    if (!doc) return;
    if (docDirty(doc) && !confirm(`Discard the unsaved changes to ${doc.id}?`)) return;
    delete S.docs[k];
    const tab = tabOf(doc.kind);
    if (S.open[tab] === k) { const other = docsOf(tab)[0]; S.open[tab] = other ? other.key : null; }
    App.render('tab');
  }
  /** Show another open document of the same tab. */
  function switchTo(k) { const doc = S.docs[k]; if (!doc) return; S.open[tabOf(doc.kind)] = k; App.render('tab'); }

  /** One undoable change: `fn(data, doc)`; the editor pane draws again (`what`: 'editor' | 'all' | 'none'). */
  function apply(doc, fn, what) {
    const before = JSON.stringify(doc.data);
    fn(doc.data, doc);
    const now = JSON.stringify(doc.data);
    if (now !== before) {
      doc.history.push(before);
      if (doc.history.length > HISTORY_MAX) doc.history.shift();
      doc.future = [];
    }
    redraw(doc, what || 'editor');
  }
  const applyFor = (doc) => (fn, what) => apply(doc, fn, what === 'all' ? 'editor' : what);
  function moduleFor(kind) {
    const tab = tabOf(kind);
    if (tab === 'creatures') return typeof Creatures !== 'undefined' ? Creatures : null;
    if (tab === 'heroes') return typeof Heroes !== 'undefined' ? Heroes : null;
    return typeof Items !== 'undefined' ? Items : null;
  }
  /** Draw a document again: 'editor' = its pane only (the list keeps its scroll); 'all' = the whole tab. */
  function redraw(doc, what) {
    if (App.S.tab !== tabOf(doc.kind)) return;
    const mod = moduleFor(doc.kind);
    if (what === 'all' || !mod || typeof mod.redraw !== 'function') { App.render('tab'); return; }
    mod.redraw(doc, what || 'editor');
    App.render('none');
  }
  function undo(tab) {
    const doc = active(tab);
    if (!doc) return;
    if (!doc.history.length) { App.status('Nothing to undo'); return; }
    doc.future.push(JSON.stringify(doc.data));
    doc.data = JSON.parse(doc.history.pop());
    redraw(doc, 'editor');
    App.status('Undone');
  }
  function redo(tab) {
    const doc = active(tab);
    if (!doc) return;
    if (!doc.future.length) { App.status('Nothing to redo'); return; }
    doc.history.push(JSON.stringify(doc.data));
    doc.data = JSON.parse(doc.future.pop());
    redraw(doc, 'editor');
    App.status('Redone');
  }
  function revert(tab) {
    const doc = active(tab);
    if (!doc || !docDirty(doc)) { App.status('Nothing to revert'); return; }
    doc.history.push(JSON.stringify(doc.data));
    doc.data = JSON.parse(doc.saved);
    doc.badJson = {};
    doc.ui.jsonText = {};
    redraw(doc, 'editor');
    App.status(`Reverted ${doc.id} to the saved file`);
  }

  /** The rules on a document now: {errors, warnings, marks}. */
  function issuesOf(doc) {
    let saved = null;
    try { saved = JSON.parse(doc.saved); } catch (_) { saved = null; }
    return M.issues(doc.kind, doc.data, {
      id: doc.id, kind: doc.kind, lists: lists(), vocab: vocab(), files: doc.files, seenCombos: seenCombos(doc), badJson: doc.badJson, saved, looks: doc.looks, record: listRecord(doc),
    });
  }

  /** Save the active document: the rules first (errors block), then POST; a 409 asks what to do. */
  async function save(tab, force) {
    const doc = active(tab);
    if (!doc || doc.saving) return;
    const iss = issuesOf(doc);
    if (iss.errors.length) {
      App.status(`Cannot save ${doc.id}: ${iss.errors.length} error${iss.errors.length > 1 ? 's' : ''} (see the editor's header)`, 'bad');
      redraw(doc, 'editor');
      return;
    }
    if (!docDirty(doc) && !force) { App.status('Nothing to save'); return; }
    doc.saving = true;
    App.status(`Saving ${doc.file || doc.id} and importing…`, 'busy');
    App.render('none');
    try {
      const { status, data: res } = await postJSON(`/api/content/${encodeURIComponent(doc.kind)}/${encodeURIComponent(doc.id)}/save`, { json: doc.data, base_mtime: force ? null : doc.baseMtime });
      doc.saving = false;
      if (status === 409) { conflict(doc, res); return; }
      if (status === 404) throw new Error('the server has no save route yet (lane S)');
      if (!res.ok) throw new Error(res.error || `HTTP ${status}`);
      doc.saved = JSON.stringify(doc.data);
      if (res.mtime != null) doc.baseMtime = res.mtime;
      const when = new Date().toLocaleTimeString();
      const changed = Array.isArray(res.changed) ? res.changed.length : null;
      const what = `${changed != null ? `${changed} key${changed === 1 ? '' : 's'}` : 'the JSON'}${Array.isArray(res.removed) && res.removed.length ? `, ${res.removed.length} removed` : ''}`;
      const backup = res.backup ? ` · backup ${String(res.backup).split(/[\\/]/).pop()}` : '';
      if (res.import_ok === null || res.import_ok === undefined) App.status(`Saved ${what} to ${doc.file || doc.id} at ${when}${res.job ? ' · import queued as a job' : ''}${backup}`, 'good', res.output);
      else if (res.import_ok) App.status(`Saved ${what} to ${doc.file || doc.id} at ${when} · import OK${backup}`, 'good', res.output);
      else App.status(`Saved ${what} to ${doc.file || doc.id} at ${when} · IMPORT FAILED (the game still plays the old .tres)`, 'bad', res.output);
      App.toast(`${doc.id} saved`);
      await refreshRecord(doc.kind, doc.id);
      await refreshList(tabOf(doc.kind) === 'creatures' ? 'enemies' : tabOf(doc.kind));
    } catch (e) {
      doc.saving = false;
      App.status(`Save failed: ${e.message}`, 'bad');
    }
    App.render('tab');
  }

  /** Pass 68: before something that reads the file and writes it again (Duplicate… copies a look's recipe from it; a
   *  job's enqueue writes the look's recipe into it), a document with unsaved changes is saved, or the action stops:
   *  the server's write would otherwise go under the open document and its next refresh would drop the unsaved looks.
   *  Resolves true when the file holds the document (saved now, or nothing to save). */
  async function ensureSaved(doc, why) {
    if (!doc || !docDirty(doc)) return true;
    if (!confirm(`${doc.id} has unsaved changes. ${why || ''}\n\nSave them now and go on? (Cancel stops here.)`)) {
      App.status(`Not done: save ${doc.id} first (${why || 'the action reads the file'})`, 'bad');
      return false;
    }
    const tab = tabOf(doc.kind);
    S.open[tab] = doc.key;
    await save(tab);
    if (docDirty(doc)) { App.status(`${doc.id} was not saved, so nothing else happened: ${why || ''}`, 'bad'); return false; }
    return true;
  }

  /** The file changed on disk since this document was opened (a job landed, a hand edit): Reload / Keep mine / Show the other. */
  function conflict(doc, res) {
    App.status(`${doc.file || doc.id} changed on disk since you opened it`, 'bad');
    const box = el('div', { class: 'amodal-back' });
    const closeIt = () => box.remove();
    const dlg = el('div', { class: 'amodal' },
      el('h3', { text: `${doc.id}.json changed on disk` }),
      el('p', { class: 'muted', text: 'Something else wrote the file since you opened it (a finished art job, a hand edit, another page). What now?' }),
      el('div', { class: 'amodal-actions' },
        el('button', { class: 'btn', type: 'button', text: 'Reload (lose my edits)', onclick: async () => { closeIt(); await open(doc.kind, doc.id, { reload: true }); } }),
        el('button', { class: 'btn danger', type: 'button', text: 'Keep mine (overwrite)', onclick: async () => { closeIt(); await save(tabOf(doc.kind), true); } }),
        el('button', { class: 'btn', type: 'button', text: 'Show the other', onclick: async () => {
          try {
            const other = await getJSON(`/api/content/${encodeURIComponent(doc.kind)}/${encodeURIComponent(doc.id)}`);
            const theirs = other.json || {}, mine = doc.data, base = JSON.parse(doc.saved);
            const keys = Array.from(new Set(Object.keys(theirs).concat(Object.keys(mine)))).filter((kk) => JSON.stringify(theirs[kk]) !== JSON.stringify(mine[kk]));
            const tbl = el('table', { class: 'kv adiff' }, el('tr', {}, el('th', { text: 'key' }), el('th', { text: 'on disk now' }), el('th', { text: 'mine' })));
            for (const kk of keys) tbl.appendChild(el('tr', { class: JSON.stringify(base[kk]) !== JSON.stringify(theirs[kk]) ? 'theirs' : '' }, el('td', { text: kk }), el('td', {}, el('pre', { text: JSON.stringify(theirs[kk], null, 1) || '(absent)' })), el('td', {}, el('pre', { text: JSON.stringify(mine[kk], null, 1) || '(absent)' }))));
            if (!keys.length) tbl.appendChild(el('tr', {}, el('td', { colspan: 3, text: 'no top-level key differs: only the file\'s layout or its time changed' })));
            const old = dlg.querySelector('.adiff'); if (old) old.remove();
            dlg.insertBefore(tbl, dlg.querySelector('.amodal-actions'));
            doc.baseMtime = other.mtime;
          } catch (e) { App.status(`Could not read the file again: ${e.message}`, 'bad'); }
        } }),
        el('button', { class: 'btn ghost', type: 'button', text: 'Cancel', onclick: closeIt })));
    box.appendChild(dlg);
    box.addEventListener('click', (e) => { if (e.target === box) closeIt(); });
    document.body.appendChild(box);
  }

  /** Read a document's record again after a look op or a landing: the looks, files and mtime; the look keys
   *  (variants / variant / variant_base) are taken from disk and count as saved, the other edits stay. */
  async function refreshRecord(kind, id) {
    const doc = S.docs[key(kind, id)];
    if (!doc) return null;
    try {
      const rec = await getJSON(`/api/content/${encodeURIComponent(kind)}/${encodeURIComponent(id)}`);
      doc.looks = rec.looks || doc.looks;
      doc.files = rec.files || doc.files;
      doc.baseMtime = rec.mtime;
      doc.text = rec.text || doc.text;
      doc.combos = rec.combos_seen || doc.combos;
      if (rec.deletable != null) doc.deletable = rec.deletable;
      if (rec.editable != null) doc.editable = rec.editable;
      doc.quest = rec.quest || null;
      doc.pathMissing = rec.path_missing || null;
      const fresh = rec.json || {};
      const before = JSON.stringify(lookFreeData(doc.data));   // pass 97: what the pane shows outside the Looks section
      if (!docDirty(doc)) { doc.data = fresh; doc.saved = JSON.stringify(fresh); }
      else {
        const saved = JSON.parse(doc.saved);
        for (const kk of ['variants', 'variant', 'variant_base']) {
          if (kk in fresh) { doc.data[kk] = fresh[kk]; saved[kk] = fresh[kk]; } else { delete doc.data[kk]; delete saved[kk]; }
        }
        // pass 70: removing the base look (or a landing on a base with its own strip) rewrites the top-level art keys; a
        // key whose value on disk differs from the one the document was read with is taken from disk too (the
        // document's own edits of a key the server did not touch stay), so a later Save never writes the old art back
        // pass 76 (lane ICON): the base's icon_history is written beside the top-level icon by the icon ops
        for (const kk of ['sprite', 'icon', 'anims', 'strip_cols', 'fps', 'frame_px', 'head', 'badge', 'icon_history']) {
          if (JSON.stringify(fresh[kk]) === JSON.stringify(saved[kk])) continue;
          if (kk in fresh) { doc.data[kk] = fresh[kk]; saved[kk] = fresh[kk]; } else { delete doc.data[kk]; delete saved[kk]; }
        }
        doc.saved = JSON.stringify(saved);
      }
      // a look that landed or an import that finished shows at once (lead, pass 66: the grid kept the old record)
      // pass 97 (lane LIVE, UI-04): only the Looks section (and the pane's header) is drawn again when nothing outside
      // the look keys changed on disk, so a field being typed, an open fold and the scroll elsewhere in the pane stay;
      // anything else changed (or no Looks section on screen): the whole pane as before
      // pass 97 (lead, the review's A1): a hero's pane holds the Puppet box and other parts that read their files once when
      // built (tools/dl/puppet), so a hero always gets the whole pane again, as before pass 97; enemies and bosses keep the
      // Looks-only redraw
      if (doc.kind === 'hero' || before !== JSON.stringify(lookFreeData(doc.data)) || !redrawLooks(doc)) redraw(doc, 'editor');
      return rec;
    } catch (e) {
      App.status(`Could not read ${id} again: ${e.message}`, 'bad');
      return null;
    }
  }

  // pass 97 (lane LIVE): the keys the Looks section draws (enemies.js / heroes.js put them in it); a refresh that changed
  // nothing else draws only that section
  const LOOK_SECTION_KEYS = ['variants', 'variant', 'variant_base', 'anims', 'strip_cols', 'frame_px', 'fps', 'directions'];
  const LOOK_SECTIONS = ['Looks', 'Looks & previews'];
  function lookFreeData(data) { const o = Object.assign({}, data || {}); for (const k of LOOK_SECTION_KEYS) delete o[k]; return o; }
  /** The doc's Looks section (and the pane's header) replaced by freshly built ones; false when the pane shows none (an
   *  item, another tab), and the caller draws the pane as before. The rest of the pane keeps its DOM. */
  function redrawLooks(doc) {
    if (typeof App === 'undefined' || App.S.tab !== tabOf(doc.kind)) return false;
    const old = doc.pane;
    if (!old || !old.isConnected) return false;
    const secOf = (pane) => [...pane.querySelectorAll('details.asection')].find((d) => LOOK_SECTIONS.includes(d.dataset.section));
    const oldSec = secOf(old);
    if (!oldSec) return false;
    const mod = moduleFor(doc.kind);
    if (!mod || typeof mod.redraw !== 'function') return false;
    // the module draws its pane through swapPane: this one time swapPane builds it aside and hands back the new section
    let built = null;
    doc.__looksOnly = (pane) => { built = pane; };
    try { mod.redraw(doc, 'editor'); } finally { doc.__looksOnly = null; doc.pane = old; }
    if (!built) return false;
    const newSec = secOf(built);
    if (!newSec) return false;
    oldSec.replaceWith(newSec);
    const oh = old.querySelector('div.ahead'), nh = built.querySelector('div.ahead');
    if (oh && nh && oh.parentNode === old) oh.replaceWith(nh);
    // the players of the sections built aside and thrown away
    for (const n of built.querySelectorAll('figure.sp')) { if (n.__sp && typeof n.__sp.destroy === 'function') n.__sp.destroy(); }
    App.render('none');
    return true;
  }

  // ------------------------------------------------------------------ server operations

  /** Create a new asset from a template (POST /api/content/<kind>) and open it. */
  async function create(kind, body) {
    App.status(`Creating ${kind} ${body.id}…`, 'busy');
    const { status, data } = await postJSON(`/api/content/${encodeURIComponent(kind)}`, body);
    if (status === 404) { App.status('The server has no create route yet (lane S)', 'bad'); return null; }
    if (!data.ok) { App.status(`Could not create ${body.id}: ${data.error || status}`, 'bad'); return null; }
    App.toast(`${body.id} created from ${body.template}${data.job ? ' · placeholders and import queued' : ''}`);
    const tab = tabOf(kind);
    await refreshList(tab === 'creatures' ? 'enemies' : tab);
    return open(data.kind || kind, data.id || body.id, { templateId: body.template });
  }
  async function deleteDoc(doc) {
    if (!confirm(`Delete ${doc.id} (its folder moves to the backups)? Only ids created in the editor can go.`)) return;
    const { status, data } = await postJSON(`/api/content/${encodeURIComponent(doc.kind)}/${encodeURIComponent(doc.id)}/delete`, {});
    if (status === 409) { App.status(`${doc.id} is still named by: ${JSON.stringify(data.refs || data.error)}`, 'bad'); return; }
    if (!data.ok) { App.status(`Could not delete ${doc.id}: ${data.error || status}`, 'bad'); return; }
    App.toast(`${doc.id} deleted (moved to ${data.moved_to || 'the backups'})`);
    delete S.docs[doc.key];
    const tab = tabOf(doc.kind);
    if (S.open[tab] === doc.key) { const other = docsOf(tab)[0]; S.open[tab] = other ? other.key : null; }
    await refreshList(tab === 'creatures' ? 'enemies' : tab);
    App.render('tab');
  }
  /** POST /api/content/weapon/<id>/make_path: the three template mutations and the template evolution, all hidden. */
  async function makePath(doc) {
    App.status(`Creating ${doc.id}'s path templates…`, 'busy');
    const { status, data } = await postJSON(`/api/content/weapon/${encodeURIComponent(doc.id)}/make_path`, {});
    if (!data.ok) { App.status(`Could not create the templates: ${data.error || status}`, 'bad'); return; }
    App.toast(`Created ${(data.created || []).join(', ')} (hidden until filled)`);
    await refreshRecord(doc.kind, doc.id);
    await refreshList('items');
    App.render('tab');
  }
  async function availabilityOp(doc, body) {
    const { status, data } = await postJSON(`/api/content/${encodeURIComponent(doc.kind)}/${encodeURIComponent(doc.id)}/availability`, body);
    if (!data.ok) { App.status(`Could not change the availability: ${data.error || status}`, 'bad'); return false; }
    App.toast(`${doc.id}: ${data.wrote || 'availability written'}${data.quest ? ` · quest ${data.quest}` : ''}`);
    await refreshRecord(doc.kind, doc.id);
    await refreshList(tabOf(doc.kind) === 'creatures' ? 'enemies' : tabOf(doc.kind));
    App.render('tab');
    return true;
  }
  /** A look op (approve / shelve / unshelve / remove / note / recipe / default) on one code. */
  async function lookOp(doc, code, body) {
    const { status, data } = await postJSON(`/api/content/${encodeURIComponent(doc.kind)}/${encodeURIComponent(doc.id)}/look/${encodeURIComponent(code)}`, body);
    if (status === 409) { App.status(`${code}: ${data.error || 'refused'}${data.refs ? ' · named by ' + JSON.stringify(data.refs) : ''}`, 'bad'); return false; }
    if (!data.ok) { App.status(`${code}: ${data.error || status}`, 'bad'); return false; }
    await refreshRecord(doc.kind, doc.id);
    if (tabOf(doc.kind) === 'creatures') await App.refreshCreatures(); else await refreshList(tabOf(doc.kind));
    App.render('tab');
    return true;
  }
  /** Test in game: the debug arena with this hero (and look) or this creature (and look), through a `launch` job. */
  async function testLaunch(doc) {
    const body = { map: 'red_canyon' };
    if (doc.kind === 'hero') { body.character = doc.id; if (doc.ui.look) body.look = doc.ui.look; }
    else if (doc.kind === 'enemy' || doc.kind === 'boss') { body.enemy = doc.id; body.variant = doc.ui.look || doc.data.variant || ''; body.count = doc.kind === 'boss' ? 1 : 3; }
    else { App.status('Test in game spawns creatures and heroes; an item is tested in the arena by hand', 'bad'); return; }
    if (docDirty(doc) && !confirm(`${doc.id} has unsaved changes: the game plays the saved file. Launch anyway?`)) return;
    App.status('Launching the game (the Godot lock is taken while the window lives)…', 'busy');
    const { status, data } = await postJSON('/api/test_launch', body);
    if (status === 404) { App.status('The server has no test_launch route yet (lane S)', 'bad'); return; }
    if (!data.ok) { App.status(`Could not launch: ${data.error || status}`, 'bad'); return; }
    App.status(`Launch queued${data.job && data.job.id ? ` as job ${data.job.id}` : ''}: the arena opens with ${body.character || body.enemy}${body.look || body.variant ? ' in ' + (body.look || body.variant) : ''}`, 'good');
    if (typeof Jobs !== 'undefined' && typeof Jobs.poll === 'function') Jobs.poll();
  }

  // ------------------------------------------------------------------ the shared UI pieces

  function statusChip(av, extra) {
    const words = { available: 'available', hidden: 'hidden', locked: 'locked by quest', purchase: 'to buy', retired: 'retired' };   // pass 69: the purchase loop is wired
    return el('span', { class: 'achip ' + (av || ''), text: words[av] || av || '' , title: extra || '' });
  }

  /** The sticky header: KIND · Name · file · N changes [Save asset] [Test in game] [more ▾] [✕], then the issues line. */
  function header(doc, iss, opts) {
    const o = opts || {};
    const changes = doc.history.length;
    const d = docDirty(doc);
    const others = docsOf(tabOf(doc.kind)).filter((x) => x.key !== doc.key);
    const h = el('div', { class: 'ahead' + (d ? ' dirty' : '') });
    // the icon of the look being edited (else the one in play), so the asset stays in view while the pane scrolls
    const lookCode = doc.ui && doc.ui.look && Array.isArray(doc.looks) && doc.looks.some((l) => l.code === doc.ui.look) ? doc.ui.look : String(doc.data.variant || doc.data.variant_base || '');
    const iconUrl = `/icon/${KIND_ICON[doc.kind] || doc.kind}/${encodeURIComponent(doc.id)}${lookCode ? '/' + encodeURIComponent(lookCode) : ''}?v=${doc.baseMtime || 0}`;
    const title = el('div', { class: 'ahead-title' },
      el('img', { class: 'ahead-icon', src: iconUrl, alt: '', width: 44, height: 44, title: `${doc.data.name || doc.id}${lookCode ? ' · look ' + lookCode : ''}`, onerror: (e) => { e.target.classList.add('none'); } }),
      // pass 73 (lane CARDS): a line item says CARD (a fortune card to the player)
      el('span', { class: 'akind ' + doc.kind, text: doc.kind === 'passive' && doc.data && doc.data.line ? 'CARD' : (KIND_LABEL[doc.kind] || doc.kind.toUpperCase()) }),
      el('b', { class: 'ahead-name', text: String(doc.data.name || doc.id), title: `${doc.kind} ${doc.id}` }),
      el('span', { class: 'muted small', text: doc.file ? doc.file.split(/[\\/]/).slice(-2).join('/') : `${doc.id}.json` }),
      el('span', { class: 'muted small achanges', text: d ? `${changes} change${changes === 1 ? '' : 's'} · unsaved` : (changes ? `${changes} change${changes === 1 ? '' : 's'} · saved` : 'as on disk') }));
    const acts = el('div', { class: 'ahead-actions' });
    if (others.length) {
      const menu = el('details', { class: 'adocs' }, el('summary', { text: `Open documents (${others.length + 1}) ▾` }));
      const list = el('div', { class: 'adocs-list' });
      for (const x of [doc].concat(others)) list.appendChild(el('button', { class: 'btn small' + (x.key === doc.key ? ' primary' : ''), type: 'button', text: `${docDirty(x) ? '● ' : ''}${x.data.name || x.id}`, onclick: () => switchTo(x.key) }));
      menu.appendChild(list);
      acts.appendChild(menu);
    }
    const saveBtn = el('button', { class: 'btn primary small' + (d && iss.errors.length ? ' blocked' : ''), type: 'button', text: doc.saving ? 'Saving…' : 'Save asset', title: iss.errors.length ? `${iss.errors.length} error(s) block the save` : 'write the JSON and import it (Ctrl+S)', disabled: !d || doc.saving, onclick: () => save(tabOf(doc.kind)) });
    acts.appendChild(saveBtn);
    acts.appendChild(el('button', { class: 'btn small', type: 'button', text: 'Undo', disabled: !doc.history.length, title: 'Ctrl+Z', onclick: () => undo(tabOf(doc.kind)) }));
    acts.appendChild(el('button', { class: 'btn small', type: 'button', text: 'Redo', disabled: !doc.future.length, title: 'Ctrl+Y', onclick: () => redo(tabOf(doc.kind)) }));
    acts.appendChild(el('button', { class: 'btn small', type: 'button', text: 'Revert', disabled: !d, title: 'back to the file as saved', onclick: () => revert(tabOf(doc.kind)) }));
    const canTest = doc.kind === 'hero' || doc.kind === 'enemy' || doc.kind === 'boss';
    acts.appendChild(el('button', { class: 'btn small', type: 'button', text: 'Test in game', disabled: !canTest, title: canTest ? 'the debug arena with this one (a launch job holds the Godot lock while the window lives)' : 'items are tried in the arena by hand', onclick: () => testLaunch(doc) }));
    const more = el('details', { class: 'adocs amore' }, el('summary', { text: '⋯' }));
    const moreList = el('div', { class: 'adocs-list' });
    moreList.appendChild(el('button', { class: 'btn small', type: 'button', text: 'Show the JSON', onclick: () => jsonPeek(doc) }));
    if (o.extraActions) for (const b of o.extraActions) moreList.appendChild(b);
    moreList.appendChild(el('button', { class: 'btn small danger', type: 'button', text: 'Delete…', title: doc.deletable === false ? 'only ids created in the editor can be deleted (the created-ids ledger)' : 'move its folder to the backups', disabled: doc.deletable === false, onclick: () => deleteDoc(doc) }));
    more.appendChild(moreList);
    acts.appendChild(more);
    acts.appendChild(el('button', { class: 'btn ghost small', type: 'button', text: '✕', title: 'close this document', onclick: () => close(doc.key) }));
    h.appendChild(title);
    h.appendChild(acts);
    h.appendChild(issuesLine(doc, iss));
    if (doc.editable === false) h.appendChild(el('div', { class: 'ferr error', text: `the server cannot edit ${doc.file || doc.id} line by line (${M.isObj(doc.layout) && doc.layout.unit === '	' ? 'tab-indented' : 'a layout it cannot keep'}): Save would be refused; ask Claude to tidy the file` }));
    if (Array.isArray(doc.pathMissing) && doc.pathMissing.length && !doc.data.hidden) h.appendChild(el('div', { class: 'ferr warn', text: `the server's availability check: ${doc.pathMissing.join('; ')}` }));
    return h;
  }

  function jsonPeek(doc) {
    const box = el('div', { class: 'amodal-back' });
    const closeIt = () => box.remove();
    box.appendChild(el('div', { class: 'amodal wide' }, el('h3', { text: `${doc.id}.json as the editor holds it` }), el('pre', { class: 'json', text: JSON.stringify(doc.data, null, 2) }), el('div', { class: 'amodal-actions' }, el('button', { class: 'btn', type: 'button', text: 'Close', onclick: closeIt }))));
    box.addEventListener('click', (e) => { if (e.target === box) closeIt(); });
    document.body.appendChild(box);
  }

  /** "▸ 1 error · 2 warnings": the list unfolds; each line jumps to its row. */
  function issuesLine(doc, iss) {
    const ne = iss.errors.length, nw = iss.warnings.length;
    const line = el('details', { class: 'aissues ' + (ne ? 'bad' : nw ? 'warn' : 'good') });
    line.open = !!doc.ui.issuesOpen;
    line.addEventListener('toggle', () => { doc.ui.issuesOpen = line.open; });
    line.appendChild(el('summary', { text: ne || nw ? `${ne ? ne + ' error' + (ne > 1 ? 's' : '') : ''}${ne && nw ? ' · ' : ''}${nw ? nw + ' warning' + (nw > 1 ? 's' : '') : ''}` : 'no issues' }));
    const ul = el('ul');
    for (const x of iss.errors.map((e) => Object.assign({ level: 'error' }, e)).concat(iss.warnings.map((w) => Object.assign({ level: 'warn' }, w)))) {
      ul.appendChild(el('li', { class: x.level }, el('a', { href: '#', text: x.key, onclick: (e) => { e.preventDefault(); jumpTo(doc, x.key); } }), el('span', { text: ' ' + x.msg })));
    }
    if (ne || nw) line.appendChild(ul);
    return line;
  }
  function jumpTo(doc, k) {
    const pane = doc.pane;
    if (!pane) return;
    let n = pane.querySelector(`[data-key="${CSS.escape(k)}"]`);
    if (!n) { const parts = k.split('.'); while (parts.length && !n) { parts.pop(); if (parts.length) n = pane.querySelector(`[data-key="${CSS.escape(parts.join('.'))}"]`); } }
    if (!n) return;
    const det = n.closest('details.asection');
    if (det && !det.open) det.open = true;
    n.scrollIntoView({ block: 'center', behavior: 'smooth' });
    n.classList.add('flash');
    setTimeout(() => n.classList.remove('flash'), 1200);
  }

  /** A collapsible section; its open state lives in doc.ui.open (the first ones open by default). */
  function section(doc, name, nodes, opts) {
    const o = opts || {};
    const id = o.id || name;
    const det = el('details', { class: 'asection' + (o.cls ? ' ' + o.cls : ''), 'data-section': id });
    det.open = doc.ui.open[id] == null ? !!o.open : !!doc.ui.open[id];
    det.addEventListener('toggle', () => { doc.ui.open[id] = det.open; });
    const sum = el('summary', {}, el('span', { class: 'asec-title', text: name }));
    if (o.chips) for (const c of o.chips) sum.appendChild(c);
    if (o.marks) { const m = o.marks; if (m.errors) sum.appendChild(el('span', { class: 'achip bad', text: `${m.errors} error${m.errors > 1 ? 's' : ''}` })); if (m.warnings) sum.appendChild(el('span', { class: 'achip warn', text: `${m.warnings} warning${m.warnings > 1 ? 's' : ''}` })); }
    det.appendChild(sum);
    const body = el('div', { class: 'asec-body' });
    for (const n of [].concat(nodes || [])) if (n) body.appendChild(n);
    if (o.foot) body.appendChild(el('p', { class: 'muted small afoot', text: o.foot }));
    det.appendChild(body);
    return det;
  }
  /** How many issues fall in a section's rows (by key prefix). */
  function sectionMarks(iss, keys) {
    let errors = 0, warnings = 0;
    for (const k of Object.keys(iss.marks)) {
      if (!keys.some((kk) => k === kk || k.startsWith(kk + '.') || kk.startsWith(k + '.'))) continue;
      if (iss.marks[k].level === 'error') errors++; else warnings++;
    }
    return { errors, warnings };
  }

  /** The placeholder of a row (its `ph`, else its default). */
  function placeholderOf(def, doc) {
    if (typeof def.ph === 'function') { try { return def.ph(doc.data, { id: doc.id, kind: doc.kind, lists: lists(), vocab: vocab() }); } catch (_) { return ''; } }
    if (def.ph != null) return def.ph;
    return def.def != null && typeof def.def !== 'boolean' ? def.def : undefined;
  }

  /** A field row for an asset document: forms.js's controls for the scalar types, this file's for the asset types;
   *  the row carries data-key and its issue marks. Returns null for the types a kind's own module places itself
   *  (attacks, look_grid, path_strip, quest_lock, band). */
  function fieldRow(doc, def, iss, opts) {
    const o = opts || {};
    if (['attacks', 'look_grid', 'path_strip', 'quest_lock', 'band'].includes(def.type)) return null;
    const apply2 = applyFor(doc);
    const ph = placeholderOf(def, doc);
    const v = vocab();
    const def2 = Object.assign({}, def);
    if (typeof def.options === 'function') def2.options = F.options(def, v);
    // pass 69: a row's `after(data, value)` runs inside the same undo step (the hero's availability keeps `hidden` in step);
    // it wraps the apply (Forms.row reads `opts.after` as a node, so it cannot ride in the options)
    const applyRow = typeof def.after === 'function' ? (fn, what) => apply2((data, d) => { fn(data, d); def.after(doc.data, U.getPath(doc.data, def.key)); }, what) : apply2;
    const ctlOpts = { apply: applyRow, placeholder: ph, path: def.key, what: 'editor', rows: o.rows, inherit: def.inherit };   // pass 70: an inherited value in the box
    let row;
    switch (def.type) {
      case 'slug': case 'readonly': {
        const val = U.getPath(doc.data, def.key);
        row = Forms.row(def2, el('span', { class: 'aread', text: val == null || val === '' ? (ph != null ? String(ph) : '—') : (typeof val === 'object' ? JSON.stringify(val) : String(val)) }), {});
        break;
      }
      case 'stat_effects': row = Forms.row(def2, statEffects(doc, def), { cls: 'wide-ctl' }); break;
      case 'level_steps': row = Forms.row(def2, levelSteps(doc, def), { cls: 'wide-ctl' }); break;
      case 'anims': row = Forms.row(def2, animsTable(doc, def), { cls: 'wide-ctl' }); break;
      case 'fps_table': row = Forms.row(def2, fpsTable(doc, def), {}); break;
      case 'sfx': row = Forms.row(def2, sfxSelect(doc, def), {}); break;
      case 'params_json': case 'json': row = Forms.row(def2, jsonBox(doc, def, o), { cls: 'wide-ctl' }); break;
      // pass 69 (lane LE, typed_forms.js): the typed params of the pass's behaviours, and a perk's special's numbers
      case 'params_fields': case 'perk_params': {
        const body = typeof TypedForms !== 'undefined' ? (def.type === 'perk_params' ? TypedForms.perkParams(doc, def, o) : TypedForms.params(doc, def, o)) : null;
        if (!body) return null;
        row = Forms.row(def2, body, { cls: 'wide-ctl' });
        break;
      }
      case 'id_select': row = Forms.row(def2, idSelect(doc, def), {}); break;
      case 'driver': row = Forms.row(def2, driverPick(doc, def), {}); break;
      case 'frame_list': row = Forms.row(def2, frameListPick(doc, def), { cls: 'wide-ctl' }); break;   // pass 93 (lane PREVIEW): death_keep
      case 'checklist': row = Forms.row(def2, checklist(doc, def2), {}); break;
      case 'tags': row = Forms.row(def2, tagsInput(doc, def), {}); break;
      case 'pickup_weights': row = Forms.row(def2, pickupWeights(doc, def), { cls: 'wide-ctl' }); break;
      case 'enemy': {
        const val = U.getPath(doc.data, def.key);
        row = Forms.row(def2, Forms.enemyPick(val || '', (nv) => apply2(() => U.setPath(doc.data, def.key, nv), 'editor'), { path: def.key, summary: false, emptyLabel: '—' }), {});
        break;
      }
      case 'shadow_scale': row = Forms.row(def2, shadowScale(doc, def), {}); break;
      case 'trait_preview': row = Forms.row(def2, traitPreview(doc), { cls: 'wide-ctl' }); break;
      case 'icon_preview': row = Forms.row(def2, iconPreview(doc, def), { cls: 'wide-ctl' }); break;
      default: {
        if (def.type === 'select' && def2.options && !def2.options.length) { row = Forms.row(def2, el('span', { class: 'muted small', text: '(no list: the server\'s vocabulary has not answered)' }), {}); break; }
        row = Forms.fieldRow(def2, doc.data, ctlOpts);
        if (def.type === 'select' && ['brain', 'archetype', 'behavior', 'targeting', 'kind', 'badge'].includes(def.key)) row.querySelector('.fctl').appendChild(el('span', { class: 'muted small vocab-foot', text: 'a new kind needs code: ask Claude', title: 'this list is the game\'s constants: listable, not extendable' }));
      }
    }
    row.dataset.key = def.key;
    markRow(row, iss, def.key);
    return row;
  }
  function markRow(row, iss, k) {
    const m = iss && iss.marks ? iss.marks[k] : null;
    if (!m) return;
    row.classList.add(m.level === 'error' ? 'has-error' : 'has-warn');
    row.appendChild(el('div', { class: 'ferr ' + m.level, text: m.msgs.join(' · ') }));
  }
  /** The rows of a section, those whose `only` allows them. */
  function rows(doc, defs, sectionName, iss, opts) {
    const out = [];
    for (const def of defs) {
      if (def.section !== sectionName) continue;
      if (typeof def.only === 'function' && !def.only(doc.data, { id: doc.id, kind: doc.kind })) continue;
      const r = fieldRow(doc, def, iss, opts);
      if (r) out.push(r);
    }
    return out;
  }
  const sectionKeys = (defs, sectionName) => defs.filter((d) => d.section === sectionName).map((d) => d.key);

  // ---- stat effects: rows of stat · op · value · target, with TextGen's wording under each
  function statEffects(doc, def) {
    const list = U.getPath(doc.data, def.key);
    const items = Array.isArray(list) ? list : [];
    const v = vocab();
    const apply2 = applyFor(doc);
    // pass 69: a level step ("levels.2") left empty stays an empty list ([]): the level is still there
    const write = (next) => apply2(() => { if (!next.length) U.setPath(doc.data, def.key, /\.\d+$/.test(def.key) ? [] : null); else U.setPath(doc.data, def.key, next); }, 'editor');
    const wrap = el('div', { class: 'seffects' });
    const statOpts = F.statOptions(def.stats || 'any', v);
    items.forEach((e, i) => {
      const eff = M.isObj(e) ? e : {};
      const set = (k2, val) => { const next = items.map((x) => Object.assign({}, M.isObj(x) ? x : {})); if (val == null || val === '') delete next[i][k2]; else next[i][k2] = val; write(next); };
      const stat = Forms.iconSelect(statOpts, eff.stat || '', (val) => set('stat', val), { emptyLabel: 'stat…', path: `${def.key}.${i}.stat`, popWidth: 360, cls: 'grow' });
      const op = Forms.select(F.options({ options: (vv) => vv.ops }, v), eff.op || 'add', (val) => set('op', val || 'add'), { path: `${def.key}.${i}.op` });
      const val = Forms.numberInput({ key: `${def.key}.${i}.value`, step: 'any' }, eff.value, (n) => set('value', n), { cls: 'short', path: `${def.key}.${i}.value` });
      let target;
      if (def.target) target = el('span', { class: 'muted small', text: `→ ${eff.target && eff.target !== def.target ? eff.target : def.target}`, title: 'the target this list implies' });
      else {
        const tv = eff.target || 'self';
        const tOpts = F.options({ options: (vv) => vv.targets }, v).filter((t) => !String(t.v).endsWith(':')).concat(tv.includes(':') ? [{ v: tv, label: tv }] : []);
        target = Forms.select(tOpts, tv, (val2) => set('target', val2 === 'self' ? null : val2), { path: `${def.key}.${i}.target` });
      }
      // pass 69: a stat with a help line (the new passive items' stats) says what it does under the card's words
      const help = eff.stat && M.statHelp ? M.statHelp(String(eff.stat), v) : '';
      const words = el('div', { class: 'muted small seffect-words', title: help, text: (eff.stat ? M.describeEffect(eff, { vocab: v, weaponName: (id) => id }) : '') + (help ? ` · ${help}` : '') });
      wrap.appendChild(el('div', { class: 'seffect' }, stat, op, val, target, el('button', { class: 'x', type: 'button', text: '×', title: 'remove', onclick: () => { const next = items.slice(); next.splice(i, 1); write(next); } }), words));
    });
    wrap.appendChild(el('button', { class: 'btn small', type: 'button', text: '+ effect', onclick: () => { const next = items.slice(); const e = { stat: statOpts[0] ? statOpts[0].v : 'damage', op: 'mul', value: 0.1 }; if (def.target && def.target !== 'self') e.target = def.target; next.push(e); write(next); } }));
    return wrap;
  }

  // ---- level steps: N lists of effects (weapons: exactly 5, level 1 empty; passives: max_level or the list's length)
  function levelSteps(doc, def) {
    const levels = Array.isArray(doc.data.levels) ? doc.data.levels : [];
    const fixed = def.fixed && !doc.data.is_evolution ? def.fixed : null;
    const n = fixed || Math.max(levels.length, 1);
    const apply2 = applyFor(doc);
    const wrap = el('div', { class: 'lsteps' });
    const base = M.isObj(doc.data.base) ? doc.data.base : {};
    // pass 95 (lane PASSIVES): a passive item's level is a rung of its rarity ladder (AFIELDS.rungName): named beside it
    const ladder = doc.kind === 'passive' && F.onLadder(doc.data);
    const rung = (lv) => (ladder ? el('span', { class: 'muted small lrung', text: `${F.rungName(doc.data.rarity, lv)} rung` }) : null);
    for (let i = 0; i < n; i++) {
      const lv = Array.isArray(levels[i]) ? levels[i] : [];
      const head = el('div', { class: 'lstep-head' }, el('b', { text: `Level ${i + 1}` }), rung(i + 1), i === 0 && fixed ? el('span', { class: 'muted small', text: 'always empty: the weapon arrives with its base numbers' }) : null,
        !fixed && i === n - 1 && n > 1 ? el('button', { class: 'x', type: 'button', text: '×', title: 'remove this level', onclick: () => apply2(() => { doc.data.levels = levels.slice(0, i); }, 'editor') }) : null);
      const body = el('div', { class: 'lstep-body' });
      if (!(i === 0 && fixed)) body.appendChild(statEffects(doc, { key: `levels.${i}`, stats: def.stats, target: def.target }));
      wrap.appendChild(el('div', { class: 'lstep' + (i === 0 && fixed ? ' locked' : '') }, head, body));
    }
    if (!fixed) wrap.appendChild(el('button', { class: 'btn small', type: 'button', text: '+ level', onclick: () => apply2(() => { if (!Array.isArray(doc.data.levels)) doc.data.levels = []; doc.data.levels.push([]); }, 'editor') }));
    if (fixed && levels.length !== fixed) wrap.appendChild(el('button', { class: 'btn small', type: 'button', text: `Make it ${fixed} levels`, onclick: () => apply2(() => { const next = levels.slice(0, fixed); while (next.length < fixed) next.push([]); next[0] = []; doc.data.levels = next; }, 'editor') }));
    if (doc.kind === 'passive' && doc.data.single && !doc.data.line && !doc.data.evolves_from) wrap.appendChild(el('div', { class: 'muted small lsum', text: 'a one-shot item (pass 100): one level, never offered again once held, no rarity ladder' }));
    if (ladder) wrap.appendChild(el('div', { class: 'muted small lsum', text: `the rarity ladder (pass 95): ${F.ladderLevels(doc.data.rarity)} levels, ${doc.data.rarity || 'common'} up to legendary, then Evolved; the game derives Max level from the rarity` }));
    const sum = M.levelsSummary(base, levels);
    if (sum.length) wrap.appendChild(el('div', { class: 'muted small lsum', text: `At level ${n}: ` + sum.map((r) => `${M.statName(r.stat)} ${M.formatValue(r.stat, r.start)} → ${M.formatValue(r.stat, r.end)}`).join(' · ') }));
    return wrap;
  }

  // ---- anims: a count per animation in the strip's pack order, total and rows
  function animsTable(doc, def) {
    const kind = doc.kind === 'hero' ? 'hero' : 'enemy';
    const anims = M.isObj(doc.data.anims) ? doc.data.anims : {};
    const apply2 = applyFor(doc);
    const wrap = el('div', { class: 'animtab' });
    const order = M.order(kind).concat(Object.keys(anims).filter((k2) => !M.order(kind).includes(k2)));
    const offs = M.offsets(anims, kind);
    for (const a of order) {
      const inp = Forms.numberInput({ key: `anims.${a}`, int: true, min: 0 }, anims[a], (nv) => apply2(() => { if (!M.isObj(doc.data.anims)) doc.data.anims = {}; if (nv == null || nv === 0) delete doc.data.anims[a]; else doc.data.anims[a] = nv; if (!Object.keys(doc.data.anims).length) delete doc.data.anims; }, 'editor'), { cls: 'tiny', path: `anims.${a}` });
      wrap.appendChild(el('label', { class: 'animcell' + (M.order(kind).includes(a) ? '' : ' unknown'), title: M.order(kind).includes(a) ? `first frame ${offs[a] < 0 ? '—' : offs[a]}` : 'not in the pack order: it still counts in the total' }, el('span', { class: 'muted small', text: a }), inp));
    }
    const total = M.totalFrames(anims), cols = Number(doc.data.strip_cols) || 0;
    wrap.appendChild(el('div', { class: 'muted small animsum', text: `${total} frames · ${cols > 0 ? `${cols} columns × ${M.rows(total, cols)} row${M.rows(total, cols) > 1 ? 's' : ''}` : 'one row'} · ${M.directions(anims)} directions` }));
    return wrap;
  }
  function fpsTable(doc, def) {
    const fps = M.isObj(doc.data.fps) ? doc.data.fps : {};
    const apply2 = applyFor(doc);
    const wrap = el('div', { class: 'animtab' });
    for (const k2 of def.keys || ['run', 'die']) {
      const inp = Forms.numberInput({ key: `fps.${k2}`, min: 0, step: 1 }, fps[k2], (nv) => apply2(() => { if (!M.isObj(doc.data.fps)) doc.data.fps = {}; if (nv == null) delete doc.data.fps[k2]; else doc.data.fps[k2] = nv; if (!Object.keys(doc.data.fps).length) delete doc.data.fps; }, 'editor'), { cls: 'tiny', path: `fps.${k2}`, placeholder: M.previewFps(doc.kind === 'hero' ? 'hero' : 'enemy', k2, {}) });
      wrap.appendChild(el('label', { class: 'animcell' }, el('span', { class: 'muted small', text: k2 }), inp));
    }
    return wrap;
  }

  // ---- sound ids: a select over the sound map with the kind's prefix first, a ▶ that plays /sound/<id>
  function sfxSelect(doc, def) {
    const v = vocab();
    const val = U.getPath(doc.data, def.key);
    const apply2 = applyFor(doc);
    const write = (nv) => apply2(() => U.setPath(doc.data, def.key, nv), 'editor');
    if (!Array.isArray(v.sounds)) {
      const inp = Forms.textInput({ key: def.key }, val, write, { path: def.key, placeholder: 'a sound id (the list comes from /api/vocab)' });
      return el('span', { class: 'with-hint' }, inp, el('span', { class: 'hint', text: 'ids from soundmap.json' }));
    }
    const pre = def.group || '';
    const mine = v.sounds.filter((s) => pre && s.startsWith(pre)).map((s) => ({ v: s, label: s }));
    const rest = v.sounds.filter((s) => !pre || !s.startsWith(pre)).map((s) => ({ v: s, label: s }));
    const sel = Forms.select(mine.length ? [{ group: pre + '*', options: mine }, { group: 'every sound', options: rest }] : rest, val || '', write, { emptyLabel: '— (silent)', path: def.key });
    const play = el('button', { class: 'btn small ghost', type: 'button', text: '▶', title: 'play it (needs the /sound route)', onclick: () => { if (!val) return; const a = new Audio('/sound/' + encodeURIComponent(val)); a.play().catch(() => App.toast('the server has no /sound route (optional)')); } });
    return el('span', { class: 'sfx-ctl' }, sel, play);
  }

  // ---- JSON boxes: a textarea with a live parse; a bad one never writes, marks doc.badJson and shows red
  function jsonBox(doc, def, opts) {
    const o = opts || {};
    const cur = U.getPath(doc.data, def.key);
    const text = doc.ui.jsonText[def.key] != null ? doc.ui.jsonText[def.key] : (cur == null ? '' : JSON.stringify(cur, null, 2));
    const ta = el('textarea', { class: 'txt area json' + (doc.badJson[def.key] ? ' bad' : ''), rows: Math.min(18, Math.max(3, text.split('\n').length + 1)), 'data-path': def.key, spellcheck: false, placeholder: def.help && def.help.startsWith('{') ? def.help : '{ }' });
    ta.value = text;
    const err = el('div', { class: 'ferr error', text: doc.badJson[def.key] || '', hidden: !doc.badJson[def.key] });
    const commit = () => {
      const t = ta.value.trim();
      if (t === '') { delete doc.badJson[def.key]; delete doc.ui.jsonText[def.key]; apply(doc, () => U.setPath(doc.data, def.key, null), 'editor'); return; }
      try {
        const parsed = JSON.parse(t);
        delete doc.badJson[def.key]; delete doc.ui.jsonText[def.key];
        apply(doc, () => U.setPath(doc.data, def.key, parsed), 'editor');
      } catch (e) {
        doc.badJson[def.key] = `not JSON: ${e.message}`;
        doc.ui.jsonText[def.key] = ta.value;
        ta.classList.add('bad');
        err.textContent = doc.badJson[def.key]; err.hidden = false;
        refreshIssues(doc);
      }
    };
    ta.addEventListener('change', commit);
    ta.addEventListener('keydown', (e) => { if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) ta.blur(); });
    const wrap = el('div', { class: 'jsonbox' });
    if (def.type === 'params_json') {
      const beh = String(doc.data.behavior || (o.behavior || '') || 'ProjectileEmitter');
      const known = Array.from(new Set((F.PARAMS_KEYS[beh] || []).concat(F.PARAMS_SHARED))).sort();
      const chips = el('div', { class: 'pchips' }, el('span', { class: 'muted small', text: `${beh} reads:` }));
      for (const k2 of (F.PARAMS_KEYS[beh] || [])) chips.appendChild(el('button', { class: 'pchip', type: 'button', text: k2, title: `insert "${k2}": at the caret`, onclick: () => insertAtCaret(ta, `"${k2}": `) }));
      const shared = el('details', { class: 'pshared' }, el('summary', { class: 'muted small', text: 'keys every weapon shares' }));
      const sl = el('div', { class: 'pchips' });
      for (const k2 of F.PARAMS_SHARED.slice().sort()) sl.appendChild(el('button', { class: 'pchip dim', type: 'button', text: k2, onclick: () => insertAtCaret(ta, `"${k2}": `) }));
      shared.appendChild(sl);
      wrap.appendChild(chips);
      wrap.appendChild(shared);
      const unknown = Object.keys(M.isObj(cur) ? cur : {}).filter((k2) => !known.includes(k2));
      if (unknown.length) wrap.appendChild(el('div', { class: 'muted small punknown' }, el('span', { class: 'ydot' }), el('span', { text: ` keys no behaviour script reads: ${unknown.join(', ')}` })));
    }
    wrap.appendChild(ta);
    wrap.appendChild(err);
    return wrap;
  }
  function insertAtCaret(ta, text) {
    const s = ta.selectionStart == null ? ta.value.length : ta.selectionStart, e = ta.selectionEnd == null ? s : ta.selectionEnd;
    ta.value = ta.value.slice(0, s) + text + ta.value.slice(e);
    ta.focus();
    ta.selectionStart = ta.selectionEnd = s + text.length;
  }
  /** The header's issues line and the top bar again without rebuilding the form (a JSON box that does not parse). */
  function refreshIssues(doc) {
    const pane = doc.pane;
    if (!pane) return;
    const iss = issuesOf(doc);
    const old = pane.querySelector('.aissues');
    if (old) old.replaceWith(issuesLine(doc, iss));
    App.render('none');
  }

  // ---- id pickers over the lists
  function idOptions(kind) {
    const fl = flatItems();
    const icon = (k2, id) => `/icon/${k2}/${encodeURIComponent(id)}`;
    const mk = (list, k2) => (list || []).map((x) => ({ v: x.id, label: x.name || x.id, icon: x.icon || icon(k2, x.id), sub: `${x.id}${x.hidden ? ' · hidden' : ''}${x.rarity ? ' · ' + x.rarity : ''}`, dim: !!x.hidden }));
    if (kind === 'hero') return mk(S.lists.heroes, 'hero');
    if (!fl) return null;
    if (kind === 'weapon') return mk(fl.weapons, 'weapon');
    if (kind === 'evolution') return mk(fl.evolutions, 'evolution');
    if (kind === 'passive') return mk(fl.passives, 'passive');
    if (kind === 'mutation') return mk(fl.mutations, 'mutation');
    if (kind === 'any_item') return [{ group: 'Weapons', options: mk(fl.weapons, 'weapon') }, { group: 'Passives', options: mk(fl.passives, 'passive') }];
    return [];
  }
  function idSelect(doc, def) {
    const val = U.getPath(doc.data, def.key);
    const apply2 = applyFor(doc);
    const write = (nv) => apply2(() => U.setPath(doc.data, def.key, nv), 'editor');
    if (def.kind === 'hero') ensureHeroes(); else ensureItems();
    const opts = idOptions(def.kind);
    if (!opts) return el('span', { class: 'with-hint' }, Forms.textInput({ key: def.key }, val, write, { path: def.key }), el('span', { class: 'hint', text: S.failed.items ? 'no /api/items yet' : 'loading the list…' }));
    const sel = Forms.iconSelect(opts, val || '', write, { emptyLabel: '—', path: def.key, size: 24, popWidth: 320 });
    if (def.readonlyWhen && def.readonlyWhen(doc)) sel.disabled = true;
    const edit = val && def.kind !== 'hero' ? el('button', { class: 'btn small ghost', type: 'button', text: 'Edit', title: `open ${val}`, onclick: () => open(def.kind === 'any_item' ? (flatItems().weapons.some((w) => w.id === val) ? 'weapon' : 'passive') : def.kind, val) }) : null;
    return el('span', { class: 'idsel' }, sel, edit);
  }

  // ---- pose / depth drivers from /api/drivers
  function driverPick(doc, def) {
    const val = U.getPath(doc.data, def.key);
    const apply2 = applyFor(doc);
    const write = (nv) => apply2(() => U.setPath(doc.data, def.key, nv), 'editor');
    ensureDrivers();
    if (!Array.isArray(S.drivers)) return el('span', { class: 'with-hint' }, Forms.textInput({ key: def.key }, val, write, { path: def.key, placeholder: 'a folder under tools/dl/drivers' }), el('span', { class: 'hint', text: S.failed.drivers ? 'no /api/drivers yet: type the folder\'s name' : 'loading the drivers…' }));
    const want = def.driverKind || null;
    const list = S.drivers.filter((d) => !want || !d.kind || d.kind === want || (want === 'depth' && d.kind === 'depth') || (want === 'pose' && d.kind !== 'depth'));
    const opts = list.map((d) => ({ v: d.name, label: d.name, sub: `${d.kind || 'pose'} · ${d.frames || '?'} frames · ${Array.isArray(d.views) ? d.views.join(' ') : ''}`, help: d.meta ? JSON.stringify(d.meta) : '' }));
    const sel = Forms.iconSelect(opts, val || '', write, { emptyLabel: '— (the default)', path: def.key, popWidth: 340 });
    // pass 93 (lane PREVIEW): the driver that applies (this field's, else the inherited or default one) plays beside it
    if (typeof Drivers === 'undefined') return sel;
    const ph = placeholderOf(def, doc);
    // an empty hero view plays gen_art's default, run
    const shown = val || (typeof ph === 'string' && ph ? ph.replace(/^\(default: |\)$/g, '') : (/(^|\.)pose_drivers\./.test(def.key) ? 'run' : ''));
    return el('span', { class: 'drv-pickwrap' }, sel, Drivers.thumb(shown, { view: typeof DriversModel !== 'undefined' ? DriversModel.viewOfKey(def.key) : 'side' }));
  }

  /** Pass 93 (lane PREVIEW): a list of frame numbers (death_keep) picked off its driver's frames (methods.json
   *  `picker: "frames"`, `frames_of`: the field naming the driver, read from this look's recipe, else the asset's own). */
  function frameListPick(doc, def) {
    const val = U.getPath(doc.data, def.key);
    const apply2 = applyFor(doc);
    const of = def.framesOf || 'death_drivers';
    const m = /^variants\.([^.]+)\.recipe\./.exec(def.key);
    const code = m ? m[1] : '';
    const ownDrv = U.getPath(doc.data, def.key.replace(/[^.]+$/, of));
    const inhDrv = m ? U.getPath(doc.data, of) : null;
    const driver = ownDrv || inhDrv || '';
    if (typeof Drivers === 'undefined') return jsonBox(doc, def, {});
    return Drivers.keepField({
      value: val, dflt: Array.isArray(def.defList) ? def.defList : undefined, driver, view: def.view || 'front',
      driverNote: ownDrv ? `this look's ${of}` : (inhDrv ? `inherited: ${doc.id}'s own ${of}` : ''),
      painted: code && (doc.kind === 'enemy' || doc.kind === 'boss') ? { enemy: doc.id, code } : null,
      label: def.label || 'Frames kept',
      onChange: (list) => apply2(() => U.setPath(doc.data, def.key, list && list.length ? list : null), 'editor'),
    });
  }

  function checklist(doc, def) {
    const cur = U.getPath(doc.data, def.key);
    const list = Array.isArray(cur) ? cur : [];
    const apply2 = applyFor(doc);
    const wrap = el('div', { class: 'checklist' });
    for (const o of def.options || []) {
      const cb = el('input', { type: 'checkbox', 'data-path': `${def.key}.${o.v}` });
      cb.checked = list.includes(o.v);
      cb.addEventListener('change', () => apply2(() => { const next = (def.options || []).map((x) => x.v).filter((vv) => (vv === o.v ? cb.checked : list.includes(vv))); if (next.length) doc.data[def.key] = next; else if (Array.isArray(doc.data[def.key])) doc.data[def.key] = []; }, 'editor'));
      wrap.appendChild(el('label', { class: 'cb', title: o.help || '' }, cb, el('span', { text: o.label })));
    }
    return wrap;
  }
  function tagsInput(doc, def) {
    const cur = U.getPath(doc.data, def.key);
    const list = Array.isArray(cur) ? cur : [];
    const apply2 = applyFor(doc);
    const write = (next) => apply2(() => { if (next.length) doc.data[def.key] = next; else delete doc.data[def.key]; }, 'editor');
    const wrap = el('div', { class: 'tagsin' });
    for (const t of list) wrap.appendChild(el('span', { class: 'tag' }, el('span', { text: t }), el('button', { class: 'x', type: 'button', text: '×', onclick: () => write(list.filter((x) => x !== t)) })));
    const fl = flatItems();
    const known = Array.from(new Set((fl ? fl.weapons.concat(fl.evolutions) : []).flatMap((w) => Array.isArray(w.tags) ? w.tags : []))).sort();
    const inp = el('input', { type: 'text', class: 'txt short', placeholder: known.length ? known.join(', ') : 'a tag', 'data-path': def.key, list: `tags-${doc.id}` });
    const dl = el('datalist', { id: `tags-${doc.id}` });
    for (const t of known) dl.appendChild(el('option', { value: t }));
    const add = () => { const t = M.slugify(inp.value); if (!t) return; inp.value = ''; if (!list.includes(t)) write(list.concat([t])); };
    inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); add(); } });
    inp.addEventListener('change', add);
    wrap.appendChild(inp);
    wrap.appendChild(dl);
    return wrap;
  }
  function pickupWeights(doc, def) {
    const cur = U.getPath(doc.data, def.key);
    const map = M.isObj(cur) ? cur : {};
    const apply2 = applyFor(doc);
    const wrap = el('div', { class: 'mini-table' }, el('div', { class: 'mini-head' }, el('span', { text: 'power-up' }), el('span', { text: 'weight' }), el('span')));
    const total = Object.values(map).reduce((a, b) => a + (Number(b) || 0), 0) || 1;
    for (const id of Object.keys(map)) {
      const sel = Forms.pickupSelect(id, (nv) => apply2(() => { const w = map[id]; delete doc.data[def.key][id]; if (nv) doc.data[def.key][nv] = w; }, 'editor'), { path: `${def.key}.${id}.id`, all: true });
      const w = Forms.numberInput({ key: `${def.key}.${id}`, min: 0, step: 'any' }, map[id], (nv) => apply2(() => { if (nv == null) delete doc.data[def.key][id]; else doc.data[def.key][id] = nv; }, 'editor'), { cls: 'short', path: `${def.key}.${id}` });
      wrap.appendChild(el('div', { class: 'mini-row' }, el('span', { class: 'cell-ico' }, sel), el('span', { class: 'with-hint' }, w, el('span', { class: 'hint', text: `${Math.round((Number(map[id]) || 0) / total * 100)}%` })), el('button', { class: 'x', type: 'button', text: '×', onclick: () => apply2(() => { delete doc.data[def.key][id]; if (!Object.keys(doc.data[def.key]).length) delete doc.data[def.key]; }, 'editor') })));
    }
    wrap.appendChild(el('button', { class: 'btn small', type: 'button', text: '+ power-up', onclick: () => apply2(() => { if (!M.isObj(doc.data[def.key])) doc.data[def.key] = {}; const used = new Set(Object.keys(doc.data[def.key])); const p = (App.S.pickups || []).find((x) => !used.has(x.id)); doc.data[def.key][p ? p.id : 'heart'] = 1; }, 'editor') }));
    return wrap;
  }
  function shadowScale(doc, def) {
    const cur = U.getPath(doc.data, def.key);
    const isList = Array.isArray(cur);
    const apply2 = applyFor(doc);
    const a = Forms.numberInput({ key: def.key + '.0', min: 0, step: 0.05 }, isList ? cur[0] : cur, (nv) => apply2(() => { if (isList) { if (nv != null) doc.data.shadow.scale[0] = nv; } else U.setPath(doc.data, def.key, nv); }, 'editor'), { cls: 'short', path: def.key + '.0', placeholder: isList ? 'width' : 'scale' });
    const b = isList ? Forms.numberInput({ key: def.key + '.1', min: 0, step: 0.05 }, cur[1], (nv) => apply2(() => { if (nv != null) doc.data.shadow.scale[1] = nv; }, 'editor'), { cls: 'short', path: def.key + '.1', placeholder: 'depth' }) : null;
    const tog = el('button', { class: 'btn small ghost', type: 'button', text: isList ? 'one number' : 'width × depth', onclick: () => apply2(() => { if (isList) U.setPath(doc.data, def.key, cur[0]); else { if (!M.isObj(doc.data.shadow)) doc.data.shadow = {}; doc.data.shadow.scale = [Number(cur) || 1, Number(cur) || 1]; } }, 'editor') });
    return el('span', { class: 'interval' }, a, b ? el('span', { class: 'hint', text: '×' }) : null, b, tog);
  }

  // ---- the hero's trait sentence (TextGen.hero_trait) and what it comes to at level 20
  function traitPreview(doc) {
    const sentence = M.heroTrait(doc.data);
    const at20 = M.heroTraitNow(doc.data, 20);
    const same = String(doc.data.trait_text || '').trim() === sentence;
    const wrap = el('div', { class: 'tpreview' },
      el('div', { class: 'tsentence', text: sentence || '(no rule: the hidden heroes read their own trait_text)' }),
      at20 ? el('div', { class: 'muted small', text: at20 }) : null,
      Array.isArray(doc.data.trait_per_level) && doc.data.trait_per_level.length && !M.heroOwnWords(doc.data) ? el('button', { class: 'btn small' + (same ? ' ghost' : ' primary'), type: 'button', text: same ? 'trait_text matches the rule' : 'Set trait_text from the rule', disabled: same, onclick: () => apply(doc, () => { doc.data.trait_text = sentence; }, 'editor') }) : null);
    return wrap;
  }

  /** The icon at 128 (the hero sheet's plate), 64 and 36, on its rarity plate (items) or round (heroes). */
  function iconPreview(doc, def) {
    const v = vocab();
    const kind = KIND_ICON[doc.kind] || doc.kind;
    const code = doc.ui.look && doc.looks.some((l) => l.code === doc.ui.look) ? '/' + encodeURIComponent(doc.ui.look) : '';
    const url = `/icon/${kind}/${encodeURIComponent(doc.id)}${code}?v=${doc.baseMtime || 0}`;
    const round = doc.kind === 'hero';
    const plate = (v.rarityPlate || F.VOCAB.rarityPlate)[String(doc.data.rarity || 'common')] || '#d2cfc7';
    const wrap = el('div', { class: 'iconprev' });
    for (const size of round ? [128, 64] : [128, 64, 36]) {
      wrap.appendChild(el('figure', { class: 'iconfig' }, el('div', { class: 'iconplate' + (round ? ' round' : ''), style: `width:${size}px;height:${size}px;${round ? '' : `background:${plate}`}` }, el('img', { src: url, alt: '', width: size, height: size, onerror: (e) => { e.target.style.visibility = 'hidden'; } })), el('figcaption', { class: 'muted small', text: `${size} px` })));
    }
    // a hero's icon is the round badge (pass 68): its candidates come from hero_badge, for the look shown (its own icon)
    // or the base look (the hero's <id>_icon.png); an item's or a creature's from icon_cands
    const lookCode = candidateCode(doc, doc.ui && doc.ui.look);
    wrap.appendChild(el('div', { class: 'icon-actions' },
      round ? el('button', { class: 'btn small', type: 'button', text: lookCode ? `+ Badge candidates for ${lookCode}…` : '+ Badge candidates…', title: `paint round badge candidates and pick one by eye (a job): the hero's words and ${lookCode ? lookCode + '\'s' : 'the base look\'s'} front still as the reference${shownWhere('badge') ? '; ' + shownWhere('badge') : ''}`, onclick: () => openJobForm(doc, { method: 'hero_badge', mode: 'badge', code: lookCode || undefined }) })
        : el('button', { class: 'btn small', type: 'button', text: '+ Icon candidates…', title: 'paint several icons and pick one by eye (a job)', onclick: () => openJobForm(doc, { method: 'icon_cands', mode: 'icon', code: lookCode || undefined }) }),
      el('span', { class: 'muted small', text: round ? `the round badge (128: the hero sheet's plate): ${shownWhere('badge') || 'the hero sheet, the results'}` : `on its ${doc.data.rarity || 'common'} plate (W.RARITY_PLATE)` })));
    // pass 76 (lane ICON): an item's icon now (the look shown, else its own), Revert icon, its changes and every icon on
    // disk with "Use for ..." (heroes and creatures have the same panel in their look grid's stage)
    if (!['hero', 'enemy', 'boss'].includes(doc.kind) && typeof LookGrid !== 'undefined' && typeof LookGrid.iconPanel === 'function') {
      wrap.appendChild(LookGrid.iconPanel(doc.kind, doc.id, lookCode, { onChanged: async () => {
        await refreshRecord(doc.kind, doc.id);
        await refreshList(tabOf(doc.kind) === 'creatures' ? 'enemies' : tabOf(doc.kind));
        App.render('tab');
      } }));
    }
    return wrap;
  }
  /** Where the game shows a hero look's badge or cut-out (LookGrid.WHERE_SHOWN): said beside every badge and cut-out
   *  candidate button (pass 68 review: the default Live title shows no cut-out). */
  function shownWhere(k) { return typeof LookGrid !== 'undefined' && LookGrid.WHERE_SHOWN && LookGrid.WHERE_SHOWN[k] ? LookGrid.WHERE_SHOWN[k] : ''; }
  /** The look a candidate job is for: `code` (the look shown) unless it is the base, whose icon and cut-out are the
   *  asset's own top-level files; '' = the base. Items have no looks. */
  function candidateCode(doc, code) {
    const look = code && Array.isArray(doc.looks) ? doc.looks.find((l) => l.code === code) : null;
    return look && !look.base && code !== String(doc.data.variant_base || '') ? String(code) : '';
  }

  /** Lane V's job form, when it is there. */
  function openJobForm(doc, opts) {
    if (typeof Jobs !== 'undefined' && typeof Jobs.openForm === 'function') return Jobs.openForm(doc.kind, doc.id, opts || {});
    App.toast('The job form (lane V) is not here yet: queue it from the Jobs tab when it lands');
    return null;
  }

  // ---- the Looks section: lane V's LookGrid + the buttons + this look's recipe
  function looksSection(doc, iss) {
    const record = listRecord(doc) || {};
    const rec = Object.assign({}, record, { variants: doc.looks.length ? doc.looks : (record.variants || record.looks || []), looks: doc.looks });
    const host = el('div', { class: 'lookhost' });
    const grid = el('div', { class: 'lookgrid-host' });
    if (typeof LookGrid !== 'undefined' && typeof LookGrid.render === 'function') {
      try { LookGrid.render(grid, rec, doc, { kind: doc.kind, id: doc.id, onSelect: (code) => { doc.ui.look = code; redraw(doc, 'editor'); }, selected: doc.ui.look, lookOp: (code, body) => lookOp(doc, code, body) }); } catch (e) { grid.appendChild(el('p', { class: 'muted small', text: `LookGrid failed: ${e.message}` })); }
    }
    if (!grid.childNodes.length) grid.appendChild(lookFallback(doc));
    host.appendChild(grid);
    const codes = doc.looks.map((l) => l.code);
    const look = doc.ui.look && codes.includes(doc.ui.look) ? doc.ui.look : (doc.data.variant || codes[0] || null);
    // the candidate buttons act on the look shown (pass 68: a look has its own icon and, for a hero, its own title cut-out),
    // the base look's going to the asset's own files
    const cand = candidateCode(doc, look);
    const forWhom = cand ? ` for ${cand}` : '';
    const bar = el('div', { class: 'look-actions' },
      el('button', { class: 'btn small primary', type: 'button', text: '+ Generate art…', title: `a new look painted by the local AI (a job); it comes with its icon candidates (a hero: badge and title cut-out candidates${doc.kind === 'hero' && shownWhere('cutout') ? `: ${shownWhere('badge')}; ${shownWhere('cutout')}` : ''})`, onclick: () => openJobForm(doc, { method: null, mode: 'look' }) }),
      doc.kind !== 'hero' ? el('button', { class: 'btn small', type: 'button', text: `+ Icon candidates${forWhom}…`, title: cand ? `icon candidates for ${cand}: its own icon (<id>_icon_<letter>.png)` : 'icon candidates for the base look (the creature\'s own <id>_icon.png)', onclick: () => openJobForm(doc, { method: 'icon_cands', code: cand || undefined, mode: 'icon' }) }) : null,
      doc.kind === 'hero' ? el('button', { class: 'btn small', type: 'button', text: `+ Badge candidates${forWhom}…`, title: (cand ? `round badge candidates for ${cand}: its own icon` : 'round badge candidates for the hero (his <id>_icon.png and badge block)') + (shownWhere('badge') ? `; ${shownWhere('badge')}` : ''), onclick: () => openJobForm(doc, { method: 'hero_badge', mode: 'badge', code: cand || undefined }) }) : null,
      doc.kind === 'hero' ? el('button', { class: 'btn small', type: 'button', text: `+ Title cut-out${forWhom}…`, title: (cand ? `title cut-out candidates for ${cand}: its own cut-out (art/ui/wanted/hero_<id>_<letter>.png)` : 'title cut-out candidates for the hero (art/ui/wanted/hero_<id>.png)') + (shownWhere('cutout') ? `; ${shownWhere('cutout')}` : ''), onclick: () => openJobForm(doc, { method: 'hero_title', mode: 'title', code: cand || undefined }) }) : null,
      // pass 92 (lane SPIDER): a creature's 3D steps had no button of their own (only the Heroes tab opened a driver form):
      // the depth driver (a clip, or a made walk / death on its back) and the leg fix, both on the driver form
      doc.kind === 'enemy' ? el('button', { class: 'btn small', type: 'button', text: '+ Depth driver…', title: 'depth videos of a rigged 3D model for creature_ctl (driver_depth): the model\'s own walk or death clip, or a walk made for its legs (mode gait) and a death on its back with the legs curled (mode flip_curl)', onclick: () => openJobForm(doc, { mode: 'driver', method: 'driver_depth' }) }) : null,
      doc.kind === 'enemy' ? el('button', { class: 'btn small', type: 'button', text: '+ Fix a model\'s legs…', title: 'a leg pair copied or turned on a rigged model (ref_limbs, tools/blender_limb_clone.py): the spider came with six legs; written as a new upload and probed', onclick: () => openJobForm(doc, { mode: 'driver', method: 'ref_limbs' }) }) : null,
      el('span', { class: 'muted small', text: `${doc.looks.length} look${doc.looks.length === 1 ? '' : 's'}${doc.looks.filter((l) => l.shelved).length ? ` · ${doc.looks.filter((l) => l.shelved).length} shelved` : ''}${doc.looks.filter((l) => l.fresh).length ? ` · ${doc.looks.filter((l) => l.fresh).length} unreviewed` : ''}` }));
    host.appendChild(bar);
    if (look) host.appendChild(recipeEditor(doc, look));
    return host;
  }
  /** The looks as a plain list when LookGrid (lane V) is not there: code, note, flags, the one-key ops. */
  function lookFallback(doc) {
    const wrap = el('div', { class: 'lookfall' });
    if (!doc.looks.length) { wrap.appendChild(el('p', { class: 'muted small', text: 'One painting (no variants block): the first look the Level Editor adds becomes a code of its own.' })); return wrap; }
    for (const l of doc.looks) {
      const isDef = l.code === (doc.data.variant || doc.data.variant_base);
      const sel = doc.ui.look === l.code;
      const rowEl = el('div', { class: 'lookrow' + (sel ? ' sel' : '') + (l.shelved ? ' shelved' : ''), onclick: () => { doc.ui.look = l.code; redraw(doc, 'editor'); } },
        el('img', { src: l.icon || `/icon/${KIND_ICON[doc.kind]}/${doc.id}/${l.code}`, alt: '', width: 40, height: 40, onerror: (e) => { e.target.style.visibility = 'hidden'; } }),
        el('b', { text: l.code }), isDef ? el('span', { class: 'achip available', text: 'in play' }) : null, l.fresh ? el('span', { class: 'achip warn', text: 'NEW' }) : null, l.shelved ? el('span', { class: 'achip hidden', text: 'shelved' }) : null,
        l.ready === false ? el('span', { class: 'achip hidden', text: 'not painted' }) : null, l.imported === false ? el('span', { class: 'achip bad', text: 'not imported' }) : null,
        el('span', { class: 'muted small', text: l.note || '' }),
        el('span', { class: 'lookops' },
          !isDef && l.ready !== false ? el('button', { class: 'btn small', type: 'button', text: 'Make default', onclick: (e) => { e.stopPropagation(); lookOp(doc, l.code, { op: 'default' }); } }) : null,
          l.fresh ? el('button', { class: 'btn small', type: 'button', text: 'Approve', onclick: (e) => { e.stopPropagation(); lookOp(doc, l.code, { op: 'approve' }); } }) : null,
          !isDef ? el('button', { class: 'btn small', type: 'button', text: l.shelved ? 'Unshelve' : 'Shelve', onclick: (e) => { e.stopPropagation(); lookOp(doc, l.code, { op: l.shelved ? 'unshelve' : 'shelve' }); } }) : null,
          !isDef ? el('button', { class: 'btn small danger', type: 'button', text: 'Remove', onclick: (e) => { e.stopPropagation(); if (confirm(`Remove look ${l.code}? Its PNGs move to the backups.`)) lookOp(doc, l.code, { op: 'remove' }); } }) : null));
      wrap.appendChild(rowEl);
    }
    wrap.appendChild(el('p', { class: 'muted small', text: 'The animated previews (StripPlayer) and the full look grid come with lane V\'s looks.js.' }));
    return wrap;
  }

  // ---- the per-look recipe: typed rows per method (methods.json's recipe_fields, else the built-in tables) + the raw JSON
  function methodOf(doc, code) {
    const entry = M.isObj(doc.data.variants) && M.isObj(doc.data.variants[code]) ? doc.data.variants[code] : {};
    const rec = M.isObj(entry.recipe) ? entry.recipe : {};
    if (rec.method) return String(rec.method);
    if (doc.kind === 'hero') return rec.pose_drivers || doc.data.pose_drivers ? (rec.still_keys ? 'hero_fit' : 'hero_pose5') : 'hero_pose5';
    if (rec.drivers) return 'creature_ctl';
    if ((rec.walk || doc.data.walk) === 'hop') return 'creature_proc';
    if (rec.pose || doc.data.pose) return 'creature_pose2';
    if (Number(rec.directions || doc.data.directions) === 8) return 'creature_free8';
    return 'creature_free2';
  }
  /** lane B's look methods (methods.json: kind enemy or hero with recipe_fields; driver / ref / item methods are jobs, not recipes) */
  const lookMethods = () => (S.methods && Array.isArray(S.methods.methods) ? S.methods.methods : []).filter((m) => Array.isArray(m.recipe_fields) && m.recipe_fields.length && (m.kind === 'enemy' || m.kind === 'hero'));
  /** The typed rows of a method's recipe from methods.json's recipe_fields (a dotted key is a path into the recipe,
   *  view_words is one box per view, file is a path under tools/dl, select options come as strings; job_fields are the
   *  job's own and never recipe keys), else the built-in tables. */
  function recipeRows(method) {
    const m = lookMethods().find((x) => x.id === method) || null;
    if (!m) return F.RECIPES[method] || F.RECIPES.creature_free2;
    const out = [];
    for (const f of m.recipe_fields) {
      const base = { key: f.key, label: f.label || f.key.replace(/^recolour\./, '').replace(/[._]/g, ' '), help: f.help || '', def: f.default != null && typeof f.default !== 'object' ? f.default : undefined };
      const t = String(f.type || 'text');
      if (t === 'view_words') {
        for (const view of Array.isArray(f.views) ? f.views : Object.keys(M.isObj(f.default) ? f.default : {})) out.push(Object.assign({}, base, { key: `${f.key}.${view}`, label: `${base.label}: ${view}`, type: 'textarea', def: undefined }));
        continue;
      }
      // pass 70: one number per view (run_scale: the size of each view's walk; lane ART's gen_art key)
      if (t === 'view_numbers') {
        for (const view of Array.isArray(f.views) ? f.views : []) out.push(Object.assign({}, base, { key: `${f.key}.${view}`, label: `${f.key === 'run_scale' ? 'Run size' : base.label}: ${view}`, type: 'number', def: typeof f.default === 'number' ? f.default : undefined, min: f.min, max: f.max, step: f.step }));
        continue;
      }
      if (t === 'driver') out.push(Object.assign(base, { type: 'driver', driverKind: /^(drivers|death_drivers)$/.test(f.key) ? 'depth' : 'pose' }));
      // pass 93 (lane PREVIEW): a list of frame numbers picked off a driver's frames (death_keep)
      else if (t === 'json' && f.picker === 'frames') out.push(Object.assign(base, { type: 'frame_list', framesOf: f.frames_of || 'death_drivers', view: f.view || 'front', defList: Array.isArray(f.default) ? f.default : undefined }));
      else if (t === 'file') out.push(Object.assign(base, { type: 'text', help: (base.help ? base.help + ' ' : '') + '(a path under tools/dl, as the upload gives it)' }));
      else if (t === 'select') out.push(Object.assign(base, { type: 'select', options: (Array.isArray(f.options) ? f.options : []).map((o) => (typeof o === 'string' ? { v: o, label: o === '' ? '(empty)' : o } : o)) }));
      else if (['bool', 'int', 'number', 'json', 'text', 'textarea'].includes(t)) out.push(Object.assign(base, { type: t }));
      else out.push(Object.assign(base, { type: 'text' }));
    }
    return out;
  }
  /** The recipe of one look as typed rows (per method), the raw JSON folded as "advanced", and the words preview. */
  function recipeEditor(doc, code) {
    ensureMethods();
    const entry = M.isObj(doc.data.variants) && M.isObj(doc.data.variants[code]) ? doc.data.variants[code] : null;
    const wrap = el('div', { class: 'recipe' });
    wrap.appendChild(el('h4', { text: `Recipe of ${code}` }, el('span', { class: 'muted small', text: entry ? '' : ' (the base strip: its recipe is the creature\'s own art words above)' })));
    if (!entry) return wrap;
    // a recipe keeps only what differs from the creature's own art words (gen_art: d.update(recipe)); the rest is
    // inherited. Garry read the empty boxes as lost prompts ("quite a few Looks ... are missing the art prompt"): every
    // field now shows the value that applies and where it comes from, and a look with no recipe at all says so.
    const rec = M.isObj(entry.recipe) ? entry.recipe : {};
    // the bookkeeping keys (the painter, the method, a draft's source, the look's own seed offset) are shown, not typed
    const book = typeof LookGrid !== 'undefined' && Array.isArray(LookGrid.BOOK_KEYS) ? LookGrid.BOOK_KEYS : ['painter', 'method', 'from', 'seed_offset'];
    const ownKeys = Object.keys(rec).filter((k) => !book.includes(k));
    const isBase = code === String(doc.data.variant_base || '');
    const pt = typeof LookGrid !== 'undefined' && typeof LookGrid.painterText === 'function' ? LookGrid.painterText : (p) => JSON.stringify(p);
    // a draft (pass 68): a recipe and no painting; Generate… paints it once the document is saved
    const lookRec = Array.isArray(doc.looks) ? doc.looks.find((l) => l.code === code) : null;
    const draft = !!lookRec && typeof LookGrid !== 'undefined' && typeof LookGrid.isDraft === 'function' && LookGrid.isDraft(lookRec, doc.kind, doc.id);
    if (draft) wrap.appendChild(el('div', { class: 'rnote draft' }, el('span', { text: `${code} is a draft${rec.from ? ' made from ' + rec.from : ''}: nothing is painted until you press Generate…. Change this recipe as you like and Save asset; Generate… opens the job form with it (it saves first if you forgot).` }),
      el('button', { class: 'btn small primary', type: 'button', text: 'Generate…', title: 'the job form for this code as a new look, with this recipe, its method and its painter', onclick: () => LookGrid.generate(doc.kind, doc.id, code) })));
    if (!ownKeys.length && isBase) wrap.appendChild(el('div', { class: 'rnote', text: 'The base strip: the creature\'s own art words (the Art section above) painted it; the fields below hold them in their boxes (italic, dashed, marked inherited). Edit one in place only to give this code a recipe of its own.' }));
    else if (!ownKeys.length) wrap.appendChild(el('div', { class: 'rnote warn', text: `No recipe was recorded for ${code}: it was painted before the Level Editor kept recipes, by hand, or by a job that ran with an empty recipe. The fields below show the creature's own words (what a job for this code would read now), which may not be what painted it. To change its art, use Duplicate… on its card (a new look from these words, under a new code) or Re-roll….` }));
    else wrap.appendChild(el('div', { class: 'rnote', text: `${ownKeys.length} own key${ownKeys.length === 1 ? '' : 's'} (${ownKeys.join(', ')}); every other field inherits the creature's own words, shown in its box (italic, dashed) and marked inherited: edit it in place to make it this look's own, empty it (or ↺) to inherit again; a box you did not change writes nothing.` }));
    const method = methodOf(doc, code);
    const methods = lookMethods().filter((m) => m.kind === (doc.kind === 'hero' ? 'hero' : 'enemy'));
    const methodOpts = (methods.length ? methods.map((m) => ({ v: m.id, label: m.name || m.id, help: m.summary || '' })) : Object.keys(F.RECIPES).filter((k2) => (doc.kind === 'hero') === k2.startsWith('hero')).map((k2) => ({ v: k2, label: k2 })));
    const mrec = methods.find((m) => m.id === method) || null;
    const apply2 = applyFor(doc);
    const base = `variants.${code}.recipe`;
    const methodSel = Forms.select(methodOpts, method, (nv) => apply2(() => { if (!M.isObj(doc.data.variants[code].recipe)) doc.data.variants[code].recipe = {}; doc.data.variants[code].recipe.method = nv; }, 'editor'), { path: `${base}.method` });
    const mnote = mrec ? `${mrec.summary || ''}${mrec.time && mrec.time.median_s ? ` · about ${Math.round(mrec.time.median_s / 60)} min (worst ${Math.round((mrec.time.worst_s || mrec.time.median_s) / 60)})` : ''}${Array.isArray(mrec.weaknesses) && mrec.weaknesses.length ? ` · weak spots: ${mrec.weaknesses.join('; ')}` : ''}` : null;
    wrap.appendChild(Forms.row({ key: `${base}.method`, label: 'Method', help: 'how this look is painted (methods.json: lane B\'s catalogue; the fields below follow it)' }, methodSel, { note: mnote }));
    // the painter it ran with (written by the job from the form's Model settings)
    const painter = M.isObj(rec.painter) ? rec.painter : null;
    wrap.appendChild(Forms.row({ key: `${base}.painter`, label: 'Painter', help: 'the model and the passes the stills were painted with: the job writes it from the form\'s Model settings (variants[CODE].recipe.painter) and, when it lands, says if the stills were reused rather than painted; Re-roll… and Generate… start from it; gen_art reads it on a hand run that names no painter' },
      el('span', { class: 'aread' + (painter ? '' : ' muted'), text: painter ? pt(painter) + (draft ? ' (what Generate… starts from)' : '') : 'not recorded (painted before the painter was kept: Flux.2 Klein with its defaults unless the job said dev)' }), {}));
    if (rec.from) wrap.appendChild(Forms.row({ key: `${base}.from`, label: 'Made from', help: 'the look Duplicate… copied this recipe from (recipe.from: bookkeeping, no tool reads it)' }, el('span', { class: 'aread', text: String(rec.from) }), {}));
    if (rec.seed_offset != null && !recipeRows(method).some((d) => d.key === 'seed_offset')) wrap.appendChild(Forms.row({ key: `${base}.seed_offset`, label: 'Seed offset', help: 'this look\'s own seeds: gen_art moves every seed it paints by N × 104729 (written when the look was first queued, from its code, so two new looks never come out as clones; a re-roll moves it on)' }, el('span', { class: 'aread', text: String(rec.seed_offset) }), {}));
    const iss = { marks: {} };
    const shown = new Set(['method', 'painter', 'from', 'seed_offset']);
    // the stills slug of a method whose form has no row for it (a hero look since pass 68: <id>_<slug>_<view>)
    if (rec.stills != null && !recipeRows(method).some((d) => String(d.key).split('.')[0] === 'stills')) {
      const own2 = doc.kind === 'hero' ? 'hero' : 'creature';
      const sRow = Forms.row({ key: `${base}.stills`, label: 'Stills slug', help: 'the slug its stills are cached under: <id>_<slug>_<view>; "" = the ' + own2 + '\'s own paintings (<id>_<view>); written by the job (a new look gets its own letter)' },
        el('span', { class: 'aread', text: rec.stills === '' ? `"" (the ${own2}'s own paintings)` : `"${rec.stills}" (its own paintings: ${doc.id}_${rec.stills}_<view>)` }), {});
      const sp0 = M.stillsProblem(rec.stills);
      if (sp0) { sRow.classList.add('has-error'); sRow.appendChild(el('div', { class: 'ferr error', text: sp0 + ': fix it in the recipe JSON below (Advanced)' })); }
      wrap.appendChild(sRow);
      shown.add('stills');
    }
    const whose = doc.kind === 'hero' ? 'the hero\'s' : 'the creature\'s';
    for (const def of recipeRows(method)) {
      shown.add(String(def.key).split('.')[0]);
      const own = U.getPath(rec, def.key);
      const inh = def.key === 'stills' ? undefined : U.getPath(doc.data, def.key);   // stills never inherits: an absent key is seeded with the look's letter
      const hasOwn = own != null && own !== '';
      const canInherit = inh != null && inh !== '' && typeof inh !== 'object';
      const inherited = !hasOwn && canInherit;
      const def2 = Object.assign({}, def, { key: `${base}.${def.key}` });
      // pass 70: a text, a hint, a prompt or a number shows the inherited value IN its box (greyed, marked), editable in
      // place: an edit makes it this look's own, emptying it inherits again, no edit writes nothing; a choice (a select, a
      // yes/no, a driver) still names it in its empty choice
      const inBox = ['text', 'textarea', 'int', 'number'].includes(def.type);
      const from = `${whose} own ${def.key} (${doc.kind === 'hero' ? 'Art words' : 'the Art section'})`;
      if (canInherit && inBox) def2.inherit = { value: inh, from };
      else if (inherited) def2.ph = typeof inh === 'boolean' ? (inh ? 'yes' : 'no') : String(inh);
      const r = fieldRow(doc, def2, iss, {});
      if (!r) continue;
      const host = r.querySelector('.fctl') || r;
      if (canInherit && inBox) {
        // the mark follows what is in the box as it is typed (Forms.inheritable's inheritchange)
        const mark = el('span', { class: 'rsrc ' + (hasOwn ? 'own' : 'inh'), text: hasOwn ? 'own' : `inherited from ${whose} ${def.key}`, title: hasOwn ? `this look's own value (variants[CODE].recipe); ${from}: ${String(inh)}` : `${from} applies: it is in the box; edit it to make it this look's own, empty it to inherit again` });
        const back = el('button', { type: 'button', class: 'btn small ghost inh-back', text: '↺ inherit', hidden: !hasOwn, title: `drop this look's own ${def.key}: ${from} applies again`,
          onclick: () => apply2(() => { U.setPath(doc.data, def2.key, null); }, 'editor') });
        host.addEventListener('inheritchange', (e) => {
          const ownNow = !!(e.detail && e.detail.own);
          mark.className = 'rsrc ' + (ownNow ? 'own' : 'inh');
          mark.textContent = ownNow ? 'own (when you leave the box)' : `inherited from ${whose} ${def.key}`;
        });
        host.appendChild(mark);
        host.appendChild(back);
      } else if (hasOwn) host.appendChild(el('span', { class: 'rsrc own', text: 'own', title: 'this look\'s own value (variants[CODE].recipe)' }));
      else if (inherited) host.appendChild(el('span', { class: 'rsrc inh', text: `inherited: ${def2.ph}`, title: `${from} applies while this is empty: ${def2.ph}` }));
      else if (def.key === 'stills') host.appendChild(el('span', { class: 'rsrc def', text: own === '' ? `empty: the ${doc.kind === 'hero' ? 'hero' : 'creature'}'s own paintings` : (lookRec && lookRec.ready === false ? 'left out: this new look gets its own letter when it is queued' : 'left out: a re-roll keeps the paintings it was made from'), title: 'the slug the stills are cached under (<id>_<slug>_front); a new look\'s job seeds the look\'s letter when the key is absent (an existing look\'s gets "", its old paintings); an explicit "" reuses the creature\'s own paintings' }));
      else if (def.def != null && def.def !== '') host.appendChild(el('span', { class: 'rsrc def', text: `default: ${def.def}`, title: 'the method\'s default (methods.json) applies while this is empty' }));
      // pass 70 (the Bandit check): Stills is the look's slug; a picture's path here is an error that blocks Save
      const sp = def.key === 'stills' ? M.stillsProblem(own) : '';
      if (sp) { r.classList.add('has-error'); r.appendChild(el('div', { class: 'ferr error', text: sp })); }
      wrap.appendChild(r);
    }
    // keys in the recipe this method's form has no row for (another tool's words: gen_ant's body, a recolour's tint_of)
    const extra = ownKeys.filter((k) => !shown.has(k));
    if (extra.length) {
      const dl = el('dl', { class: 'rextra' });
      for (const k of extra) { dl.appendChild(el('dt', { text: k })); dl.appendChild(el('dd', { text: typeof rec[k] === 'object' ? JSON.stringify(rec[k]) : String(rec[k]) })); }
      wrap.appendChild(Forms.row({ key: `${base}.extra`, label: 'Also in the recipe', help: 'keys this method\'s form has no field for: another tool\'s words (gen_ant\'s body, a recolour\'s tint_of, …); edit them in the JSON below' }, dl, { cls: 'wide-ctl' }));
    }
    const note = Forms.row({ key: `variants.${code}.note`, label: 'Note', help: 'shown on the look\'s card and the arena chip' }, Forms.textareaInput({ key: `variants.${code}.note` }, entry.note, (nv) => apply2(() => { if (nv == null) delete doc.data.variants[code].note; else doc.data.variants[code].note = nv; }, 'editor'), { path: `variants.${code}.note` }), {});
    wrap.appendChild(note);
    const adv = el('details', { class: 'asection sub' }, el('summary', { text: 'Advanced: the recipe as JSON' }));
    adv.appendChild(jsonBox(doc, { key: base, type: 'json', help: 'the whole recipe block' }, {}));
    wrap.appendChild(adv);
    const words = el('details', { class: 'asection sub' }, el('summary', { text: 'Show the words that will be sent' }));
    words.appendChild(wordsPreview(doc, code, method));
    wrap.appendChild(words);
    return wrap;
  }
  /** The prompts as the painter will see them, composed from the reference wordings and this look's fields (the
   *  authoritative dry run is asset_job.py --dry-run from the job card). */
  function wordsPreview(doc, code, method) {
    const entry = M.isObj(doc.data.variants) && M.isObj(doc.data.variants[code]) ? doc.data.variants[code] : {};
    const rec = Object.assign({}, doc.data, M.isObj(entry.recipe) ? entry.recipe : {});
    const wordings = S.methods && Array.isArray(S.methods.ref_wordings) ? S.methods.ref_wordings : F.WORDINGS;
    const subject = rec.art_prompt || rec.prompt || `a goofy ${doc.data.name || doc.id} creature, ${doc.data.flavour || ''}`;
    const fill = (t) => String(t).replace(/<subject>/g, subject).replace(/<prompt>/g, rec.prompt || subject).replace(/<noun>/g, rec.noun || 'a creature').replace(/<blockout>/g, rec.blockout || '…')
      .replace(/<detail>/g, rec.detail || '…').replace(/<anatomy>/g, rec.anatomy || '…').replace(/<keep>/g, rec.keep || '…').replace(/<back_hint>/g, rec.back_hint || '').replace(/<view>/g, 'full body, front view')
      .replace(/<STYLE>/g, '[the style sentence]').replace(/<bg>/g, `[a plain ${rec.screen || 'green'} background]`).replace(/<n>th/g, 'second').replace(/<words\[view\]>/g, (M.isObj(rec.words) && rec.words.front) || '…');
    const wrap = el('div', { class: 'words' });
    wrap.appendChild(el('p', { class: 'muted small', text: `Method ${method}. The painter receives the style anchor first, then this look's references, with these sentences (the exact text lives in the tools named; the job card's dry run shows what really goes out).` }));
    // the roles as methods.json names them (style, identity, pose, view, held object, mark); the built-in table's older names map onto them
    const roleOf = (w) => ({ 'pose-and-anatomy': 'pose', 'same figure, another view': 'view', 'held object (title)': 'held object' }[w.role] || w.role);
    const wanted = method === 'creature_ctl' ? ['style', 'pose', 'identity'] : method === 'front_from_picture' ? ['identity'] : method.startsWith('hero') ? ['style', 'view', 'identity', 'held object'] : ['style', 'view', 'identity'];
    for (const w of wordings.filter((x) => wanted.includes(roleOf(x)) && x.text)) wrap.appendChild(el('div', { class: 'wording' }, el('div', { class: 'muted small', text: `${roleOf(w)} · ${w.level}${w.source ? ' · ' + w.source : ''}${w.refs ? ' · refs ' + w.refs : ''}${w.where ? ' · ' + w.where : ''}` }), el('div', { class: 'wtext', text: fill(w.text) })));
    if (rec.motion || rec.pose_motion) wrap.appendChild(el('div', { class: 'wording' }, el('div', { class: 'muted small', text: 'the clip\'s motion (Wan)' }), el('div', { class: 'wtext', text: rec.pose_motion || rec.motion })));
    if (rec.anim_negative) wrap.appendChild(el('div', { class: 'wording' }, el('div', { class: 'muted small', text: 'never in a clip (negative)' }), el('div', { class: 'wtext', text: rec.anim_negative })));
    return wrap;
  }

  // ---- the create dialog ("+ New from template")
  /** An inline form: the template (a picture list of the kind's assets), the id (live-checked), name, flavour, doc, copy
   *  the art. `templates`: [{v, label, icon, sub}] or groups; `takenIds`: a Set; `onCreate(body)`. */
  function createDialog(kind, templates, takenIds, opts) {
    const o = opts || {};
    const state = { template: o.template || '', id: '', name: '', flavour: '', doc: '', copy_art: false };
    const box = el('div', { class: 'acreate card' });
    box.appendChild(el('h2', { text: `New ${o.label || kind} from a template` }));
    const idErr = el('div', { class: 'ferr error', hidden: true });
    const checkId = () => {
      const id = state.id;
      let msg = '';
      if (!id) msg = 'an id is needed: [a-z0-9_]';
      else if (!M.slugOk(id)) msg = 'only a-z, 0-9 and _';
      else if (takenIds && takenIds.has(id)) msg = `"${id}" exists already`;
      else if (id.startsWith('training_dummy')) msg = 'training_dummy* ids are the arena\'s';
      idErr.textContent = msg; idErr.hidden = !msg;
      return !msg;
    };
    // the picture list never redraws its own face (its other callers re-render the whole form): draw it again on a pick,
    // so the chosen template shows on the button (lead, pass 66)
    const tmpl = el('span', { class: 'cb-wrap' });
    const drawTmpl = () => {
      U.clear(tmpl);
      tmpl.appendChild(Forms.iconSelect(templates, state.template, (v) => { state.template = v || ''; drawTmpl(); },
        { emptyLabel: 'pick a template…', path: 'create.template', size: 28, popWidth: 340, cls: 'wide' }));
    };
    drawTmpl();
    const idIn = el('input', { type: 'text', class: 'txt', placeholder: 'new_id', 'data-path': 'create.id', spellcheck: false });
    idIn.addEventListener('input', () => { state.id = idIn.value.trim().toLowerCase(); checkId(); });
    const nameIn = el('input', { type: 'text', class: 'txt', placeholder: 'Name', 'data-path': 'create.name' });
    nameIn.addEventListener('input', () => { state.name = nameIn.value; if (!idIn.value) { idIn.value = M.slugify(nameIn.value); state.id = idIn.value; checkId(); } });
    const flavIn = el('input', { type: 'text', class: 'txt wide', placeholder: 'one line of flavour', 'data-path': 'create.flavour' });
    flavIn.addEventListener('input', () => { state.flavour = flavIn.value; });
    const docIn = el('textarea', { class: 'txt area', rows: 2, placeholder: o.docRequired ? 'what it is, in one line (required: the Collection reads it)' : 'what it is, in one line', 'data-path': 'create.doc' });
    docIn.addEventListener('input', () => { state.doc = docIn.value; });
    const copy = el('input', { type: 'checkbox' });
    copy.addEventListener('change', () => { state.copy_art = copy.checked; });
    box.appendChild(Forms.row({ key: 'create.template', label: 'Template', help: 'the asset this one starts as a copy of (its numbers and art words; its looks and PNGs only with "copy the art")' }, tmpl, {}));
    box.appendChild(Forms.row({ key: 'create.name', label: 'Name', required: true }, nameIn, {}));
    const idRow = Forms.row({ key: 'create.id', label: 'Id', required: true, help: 'the folder\'s name: [a-z0-9_], unique across every content type' }, idIn, {});
    idRow.appendChild(idErr);
    box.appendChild(idRow);
    box.appendChild(Forms.row({ key: 'create.flavour', label: 'Flavour' }, flavIn, {}));
    box.appendChild(Forms.row({ key: 'create.doc', label: 'Doc', required: !!o.docRequired, help: 'the Collection page\'s line (a test wants every creature to have one)' }, docIn, {}));
    if (o.copyArt !== false) box.appendChild(Forms.row({ key: 'create.copy_art', label: 'Copy the template\'s art', help: 'its strips and icons renamed (else a placeholder strip and icon are generated)' }, el('span', { class: 'cb-wrap' }, copy), {}));
    const note = el('p', { class: 'muted small', text: o.note || '' });
    if (o.note) box.appendChild(note);
    box.appendChild(el('div', { class: 'alt-actions' },
      el('button', { class: 'btn primary small', type: 'button', text: 'Create', onclick: async () => {
        if (!state.template) { App.status('Pick a template first', 'bad'); return; }
        if (!checkId()) { App.status(idErr.textContent, 'bad'); return; }
        if (!state.name.trim()) { App.status('A name is needed', 'bad'); return; }
        if (o.docRequired && !state.doc.trim()) { App.status('A doc line is needed (a test wants it)', 'bad'); return; }
        const body = { id: state.id, template: state.template, name: state.name.trim(), flavour: state.flavour.trim(), doc: state.doc.trim(), copy_art: state.copy_art };
        if (o.fields) Object.assign(body, o.fields);
        if (o.onCreate) await o.onCreate(body); else await create(kind, body);
      } }),
      el('button', { class: 'btn small ghost', type: 'button', text: 'Cancel', onclick: () => { if (o.onCancel) o.onCancel(); else box.remove(); } })));
    return box;
  }

  // ------------------------------------------------------------------ the editor pane (built once, swapped in place on edits)

  /** A fresh editor pane for `doc`: `build(pane)` fills it; doc.pane remembers it for redraws and issue jumps. */
  function buildPane(doc, build) {
    const pane = el('div', { class: 'aeditor', 'data-doc': doc.key });
    doc.pane = pane;
    build(pane);
    return pane;
  }
  /** Draw the pane again in place, keeping its scroll and the focused box (by data-path), like Settings.render does. */
  function swapPane(doc, build) {
    const old = doc.pane;
    if (!old || !old.parentNode) return false;
    // pass 97: redrawLooks asks for the pane built aside (only its Looks section and header are kept)
    if (typeof doc.__looksOnly === 'function') { const pane = buildPane(doc, build); doc.pane = old; doc.__looksOnly(pane); return true; }
    Forms.closePop();
    const scroll = old.scrollTop;
    const act = old.contains(document.activeElement) && document.activeElement.dataset ? document.activeElement.dataset.path : null;
    const pane = buildPane(doc, build);
    old.replaceWith(pane);
    pane.scrollTop = scroll;
    if (act) { const again = pane.querySelector(`[data-path="${CSS.escape(act)}"]`); if (again && typeof again.focus === 'function') again.focus({ preventScroll: true }); }
    return true;
  }

  // ------------------------------------------------------------------ dispatch

  function render(tab, panel) {
    if (tab === 'heroes' && typeof Heroes !== 'undefined') return Heroes.render(panel);
    if (tab === 'items' && typeof Items !== 'undefined') return Items.render(panel);
    if (tab === 'jobs' && typeof Jobs !== 'undefined') return Jobs.render(panel);
    panel.textContent = '';
    return panel;
  }

  return {
    S, KIND_TAB, KIND_LABEL, HISTORY_MAX,
    owns, hasDoc, active, docsOf, docDirty, dirty, anyDirty, open, close, switchTo, apply, applyFor, redraw, undo, redo, revert, save, ensureSaved, refreshRecord, issuesOf, candidateCode,
    getJSON, postJSON, ensureHeroes, ensureItems, ensureVocab, ensureMethods, ensureDrivers, refreshList, mapTl, vocab, flatItems, lists, listRecord, seenCombos,
    create, deleteDoc, makePath, availabilityOp, lookOp, testLaunch, openJobForm,
    statusChip, header, issuesLine, jumpTo, section, sectionMarks, fieldRow, markRow, rows, sectionKeys, placeholderOf, statEffects, levelSteps, animsTable, fpsTable, sfxSelect, jsonBox, idSelect, idOptions, driverPick, checklist, tagsInput, pickupWeights,
    traitPreview, iconPreview, looksSection, recipeEditor, wordsPreview, methodOf, createDialog, refreshIssues, buildPane, swapPane, render,
  };
})();
