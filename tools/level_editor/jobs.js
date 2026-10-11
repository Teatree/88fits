// The Jobs tab (pass 66, lane V): the local AI's queue as Garry asked for it ("a list of jobs that are in queue for the
// local AI, which are being worked on and as much detail about those jobs as possible ... cancel the jobs and edit them
// (while they are not running) ... add as many as I like"). A card per job, grouped by state: RUNNING (the stage, the
// elapsed time against a "~" estimate, the stages done, the last 12 log lines, Cancel, Open asset), WAITING FOR PICK (the
// candidates, click to zoom, Pick, Re-roll N more, Cancel), QUEUED (Edit, up / down, Cancel), DONE (what was written and
// how, the outputs: stills with their QA verdict, clips played, the strip; Open look, Re-queue, Hide; for a merge the
// writer could not make line-preserving the two explicit clicks "Merge again" and "Re-dump this file (changes its
// layout)"), FAILED / INTERRUPTED / CANCELLED (the error, Re-queue, Log, Delete, and "remove the stub" for a look job
// that left an entry without a strip). The header reads /api/status: the two locks (ComfyUI, Godot: free, held by whom,
// or held by an unknown process with a Force release), Blender found or not, the vision QA online or not.
//
// Polling: GET /api/jobs?since=<rev> every 2 s while the Jobs tab (or a job card) is on screen, every 6 s otherwise
// for the badge, nothing while the document is hidden, every 15 s while the server has no jobs API yet. The badge in
// the tab button shows running · queued (red with the count when a pick waits); a job that finishes, fails or asks for
// a pick raises a toast with an "open" button. jobs.js starts its own polling when the script loads.
//
// The job form (Jobs.openForm(kind, id, {method, code, mode: look | icon | badge | title | driver, job})): the method
// cards from methods.json (Garry: "they should be explained well enough, with some level of small visuals, maybe an
// example, so that I can choose them in an informed manner"), the method's recipe fields, the 2D reference rows (role
// and follow level: "References steer by which pictures are passed, in what order, and the words; there is no strength
// number"), the 3D reference rows (the driver library with its sheets played, or an upload with the preferred format
// stated and what the probe says the model can do), one row per look to paint with the codes it will get, the counts,
// seeds and re-roll options, "Show the words that will be sent", and Queue: one POST /api/jobs per look.
'use strict';

const Jobs = (() => {
  const { el, clear, fmtT } = U;
  const FAST = 2000, SLOW = 6000, MISSING = 15000;
  const LOG_LINES = 12;
  const COMFY_URL = 'http://192.168.137.54:8188/';   // the AI server's ComfyUI page (the workflow files are dragged into it)
  const STATES = ['running', 'waiting', 'queued', 'done', 'failed', 'interrupted', 'cancelled'];
  const FINISHED = ['done', 'failed', 'interrupted', 'cancelled'];
  const STATE_LABEL = { queued: 'QUEUED', running: 'RUNNING', waiting: 'WAITING FOR PICK', done: 'DONE', failed: 'FAILED', interrupted: 'INTERRUPTED', cancelled: 'CANCELLED' };
  const GROUPS = [['running', 'Running'], ['waiting', 'Waiting for a pick'], ['queued', 'Queued'], ['finished', 'Finished']];
  const TAB_OF_KIND = { enemy: 'creatures', boss: 'creatures', hero: 'heroes', weapon: 'items', evolution: 'items', passive: 'items', mutation: 'items' };
  const ROLES = [{ v: 'identity', label: 'identity (what it looks like)' }, { v: 'style', label: 'style (how it is drawn)' }, { v: 'pose', label: 'pose and anatomy' }];
  const FOLLOW = [{ v: 'loosely', label: 'follow loosely' }, { v: 'closely', label: 'follow closely' }, { v: 'copy', label: 'copy exactly' }];
  const USES = [{ v: 'animation', label: 'animation (how it moves)' }, { v: 'look', label: 'look (the painting reference)' }, { v: 'icon', label: 'icon (the icon render)' }];
  const REROLL = [
    { v: 'seeds', label: 'new seeds', help: 'every still and clip rolled again with the next seeds' },
    { v: 'clips', label: 'keep the stills, redo the clips', help: 'the painted stills stay; the clip folders move to <key>_old<stamp> and the walks are made again' },
    { v: 'view', label: 'redo one view', help: 'one view painted again as candidates to pick from (gen_ctl --view-cands)' },
    { v: 'stills', label: 'repaint the stills', help: 'the stills painted again (--force --keys), the clips follow' },
  ];
  const S = {
    rev: 0, jobs: [], status: null, statusAt: 0, timer: 0, last: null, hidden: new Set(), apiMissing: false, panel: null,
    groups: null, cards: new Map(), sigs: new Map(), methods: null, methodsP: null, drivers: null, refs: null, lists: {}, confirm: null, started: false,
    specs: undefined,   // GET /api/jobs/specs: jobs.py's SPECS {kind: {lane, fields: {name: {type, default, required, help, options}}}}; null = not served
  };
  // a job's spec as jobs.py validates it is FLAT (method, recipe, refs, drivers, skip_qa, dev, seed, seeds, keys, ...);
  // the form edits a nested state (flags, counts, job) and flattens it on Queue / Save (flatten), unflattens on Edit
  const FLAG_KEYS = ['skip_qa', 'dev', 'no_video', 'no_style_ref'];
  const OWN_KEYS = ['method', 'recipe', 'refs', 'drivers', 'note', 'seed', 'seeds'].concat(FLAG_KEYS);

  function unflatten(flat) {
    const f = flat && typeof flat === 'object' ? flat : {};
    const out = {
      method: f.method || '', recipe: f.recipe && typeof f.recipe === 'object' ? JSON.parse(JSON.stringify(f.recipe)) : {},
      refs: Array.isArray(f.refs) ? JSON.parse(JSON.stringify(f.refs)) : [], drivers: f.drivers && typeof f.drivers === 'object' ? Object.assign({}, f.drivers) : {},
      flags: { skip_qa: !!f.skip_qa, dev: !!f.dev, seed: Number(f.seed) || 0, no_video: !!f.no_video, no_style_ref: !!f.no_style_ref },
      counts: { seeds: f.seeds != null ? Number(f.seeds) : 3, looks: 1, icon_candidates: 0, cutout_candidates: 0 },
      reroll: f.reroll && typeof f.reroll === 'object' ? Object.assign({ mode: '' }, f.reroll) : { mode: '' }, note: f.note || '', job: {}, refs3d: [],
    };
    if (f.flags && typeof f.flags === 'object') Object.assign(out.flags, f.flags);
    if (f.counts && typeof f.counts === 'object') Object.assign(out.counts, f.counts);
    for (const k of Object.keys(f)) if (!OWN_KEYS.includes(k) && !['flags', 'counts', 'reroll', 'refs3d', 'job'].includes(k)) out.job[k] = f[k];
    if (f.job && typeof f.job === 'object') Object.assign(out.job, f.job);
    return out;
  }
  /** The flat spec for `jk`; with the served SPECS only the keys jobs.py validates go out (and a required default fills in). */
  function flatten(spec, jk, specs) {
    const out = { method: spec.method, recipe: spec.recipe || {}, refs: spec.refs || [], drivers: spec.drivers || {}, note: spec.note || '' };
    for (const k of FLAG_KEYS) if (spec.flags && spec.flags[k]) out[k] = true;
    if (spec.flags && spec.flags.seed) out.seed = spec.flags.seed;
    if (spec.counts && spec.counts.seeds) out.seeds = spec.counts.seeds;
    for (const [k, v] of Object.entries(spec.job || {})) if (v !== null && v !== undefined && v !== '') out[k] = v;
    if (spec.reroll && spec.reroll.mode) out.reroll = spec.reroll;
    const fields = specs && specs[jk] && specs[jk].fields && typeof specs[jk].fields === 'object' ? specs[jk].fields : null;
    if (fields) {
      for (const k of Object.keys(out)) if (!(k in fields)) delete out[k];
      for (const [k, f] of Object.entries(fields)) if (out[k] === undefined && f && f.required && f.default !== undefined && f.default !== null && f.default !== '') out[k] = f.default;
    }
    return out;
  }
  function seedOf(j) { const s = j && j.spec ? j.spec : {}; return Number(s.seed != null ? s.seed : (s.flags && s.flags.seed)) || 0; }
  function specType(t) { return { str: 'text', string: 'text', float: 'number', list: 'json', dict: 'json', path: 'file', enum: 'select', choice: 'select', integer: 'int', boolean: 'bool' }[t] || t || 'text'; }
  async function fetchSpecs() {
    if (S.specs !== undefined) return S.specs;
    const r = await fetchJson('/api/jobs/specs', null);
    let specs = null;
    if (r && typeof r === 'object') { specs = r.specs && typeof r.specs === 'object' ? r.specs : (r.ok === undefined || Object.keys(r).some((k) => r[k] && r[k].fields) ? r : null); }
    if (specs) { specs = Object.assign({}, specs); delete specs.ok; }
    S.specs = specs && Object.keys(specs).length ? specs : null;
    return S.specs;
  }

  // ------------------------------------------------------------------ polling, the badge, the toasts

  function start() {
    if (S.started) return;
    S.started = true;
    document.addEventListener('visibilitychange', () => { if (!document.hidden) poll(); });
    schedule(300);
  }
  function schedule(ms) { clearTimeout(S.timer); S.timer = setTimeout(poll, ms); }
  function onScreen() { return (typeof App !== 'undefined' && App.S && App.S.tab === 'jobs') || !!document.querySelector('.jcard'); }

  async function poll() {
    clearTimeout(S.timer);
    if (document.hidden) { schedule(SLOW); return; }
    let next = onScreen() ? FAST : SLOW;
    try {
      const r = await fetch(`/api/jobs?since=${S.rev}`, { cache: 'no-store' });
      if (r.status === 404) { S.apiMissing = true; next = MISSING; }
      else {
        const d = await r.json();
        if (d && d.ok === false) { S.apiMissing = true; next = MISSING; S.apiError = d.error || ''; }
        else if (d && !d.unchanged) { S.apiMissing = false; applyList(d); }
        else S.apiMissing = false;
      }
    } catch (e) { S.apiMissing = true; S.apiError = e.message; next = MISSING; }
    if (!S.apiMissing && App.S.tab === 'jobs' && Date.now() - S.statusAt > 4000) await fetchStatus();
    if (App.S.tab === 'jobs' && S.panel && S.panel.isConnected) drawHeader();
    schedule(next);
  }

  async function fetchStatus() {
    try {
      const r = await fetch('/api/status', { cache: 'no-store' });
      S.status = await r.json();
    } catch (_) { S.status = null; }
    S.statusAt = Date.now();
  }

  function applyList(d) {
    S.rev = d.rev || S.rev;
    const jobs = Array.isArray(d.jobs) ? d.jobs : [];
    if (S.last) {
      for (const j of jobs) {
        const was = S.last.get(j.id);
        if (was === j.state) continue;
        if (was === undefined && !['done', 'failed', 'waiting'].includes(j.state)) continue;   // a job created elsewhere: no toast until it changes
        transition(j, was);
      }
    }
    S.last = new Map(jobs.map((j) => [j.id, j.state]));
    S.jobs = jobs;
    updateBadge();
    if (App.S.tab === 'jobs' && S.panel && S.panel.isConnected) draw();
    // a look card of the open document shows the job's state: let the grid redraw its chips
    if (typeof LookGrid !== 'undefined' && document.querySelector('.lookgrid') && d.jobs) { /* chips read Jobs.jobsFor on the next render */ }
  }

  // the content kinds the server names in an import job's targets ("enemies/test_beast") -> the page's kinds
  const FOLDER_KIND = { enemies: 'enemy', bosses: 'boss', characters: 'hero', weapons: 'weapon', evolutions: 'evolution', passives: 'passive', mutations: 'mutation' };

  /** A finished job's asset, read again from disk if its document is open (lead, pass 66): the look grid then shows the
   *  landed strip, the import flag and the NEW chip without a reload. */
  function refreshTargets(j) {
    if (typeof Assets === 'undefined' || typeof Assets.refreshRecord !== 'function') return;
    const t = j.target || {};
    const pairs = [];
    if (t.kind && t.id) pairs.push([t.kind, t.id]);
    if (j.kind === 'import' || j.kind === 'register') {
      for (const x of ((j.spec || {}).targets || [])) {
        const [folder, id] = String(x).split('/');
        if (FOLDER_KIND[folder] && id) pairs.push([FOLDER_KIND[folder], id]);
      }
    }
    for (const [kind, id] of pairs) { try { Assets.refreshRecord(kind, id); } catch (_) { /* shown on the next render */ } }
  }

  function transition(j, was) {
    const t = j.target || {};
    const what = `${title(j)}`;
    if (j.state === 'done') refreshTargets(j);
    if (j.state === 'done') toast(`${what} finished${j.written && j.written.layout === 'unmerged' ? ' (the JSON needs a merge: see the Jobs tab)' : ''}`, { label: t.code ? 'Open look' : 'Open', onClick: () => openAsset(t) });
    else if (j.state === 'waiting') toast(`${what} needs a pick`, { label: 'Open Jobs', onClick: () => App.switchTab('jobs') });
    else if (j.state === 'failed') toast(`${what} failed: ${String(j.error || '').slice(0, 120)}`, { label: 'Open Jobs', onClick: () => App.switchTab('jobs'), ms: 14000 });
    else if (j.state === 'interrupted' && was === 'running') toast(`${what} was interrupted (the server restarted)`, { label: 'Open Jobs', onClick: () => App.switchTab('jobs') });
  }

  function updateBadge() {
    const b = document.getElementById('jobs-badge');
    if (!b) return;
    const n = (st) => S.jobs.filter((j) => j.state === st).length;
    const q = n('queued'), r = n('running'), w = n('waiting');
    if (!q && !r && !w) { b.hidden = true; b.textContent = ''; return; }
    const parts = [];
    if (r) parts.push('▸' + r);
    if (q) parts.push(String(q));
    if (w) parts.push('?' + w);
    b.textContent = parts.join('·');
    b.classList.toggle('waiting', w > 0);
    b.hidden = false;
    const run = S.jobs.find((j) => j.state === 'running');
    b.title = (w ? `${w} job${w > 1 ? 's' : ''} waiting for your pick · ` : '') + (run ? `running: ${title(run)}${run.progress && run.progress.stage ? ' · ' + run.progress.stage : ''}` : '') + (q ? ` · ${q} queued` : '');
  }

  /** A toast like App.toast's, with a button that opens something. */
  function toast(msg, opts) {
    const host = document.getElementById('toasts');
    if (!host) return;
    const o = opts || {};
    const t = el('div', { class: 'toast' }, el('span', { text: msg }));
    if (o.label && o.onClick) t.appendChild(el('button', { type: 'button', class: 'btn small open', text: o.label, onclick: () => { o.onClick(); t.remove(); } }));
    t.appendChild(el('button', { type: 'button', class: 'btn small ghost', text: '✕', title: 'dismiss', onclick: () => t.remove() }));
    host.appendChild(t);
    setTimeout(() => t.classList.add('show'), 10);
    setTimeout(() => { t.classList.remove('show'); setTimeout(() => t.remove(), 300); }, o.ms || 9000);
  }

  // ------------------------------------------------------------------ helpers

  function title(j) { return j.title || `${j.kind}${j.target ? ' ' + (j.target.id || '') + (j.target.code ? ' ' + j.target.code : '') : ''}`; }
  function shortId(id) { const m = /-([0-9a-f]{4})$/.exec(id || ''); return m ? m[1] : String(id || '').slice(-4); }
  function when(s) {
    if (!s) return '';
    const d = typeof s === 'number' ? new Date(s * (s < 1e12 ? 1000 : 1)) : new Date(s);
    if (isNaN(d.getTime())) return String(s);
    const today = new Date();
    const hm = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
    return d.toDateString() === today.toDateString() ? hm : `${d.getMonth() + 1}/${d.getDate()} ${hm}`;
  }
  function secondsSince(s) {
    if (!s) return 0;
    const d = typeof s === 'number' ? new Date(s * (s < 1e12 ? 1000 : 1)) : new Date(s);
    return isNaN(d.getTime()) ? 0 : Math.max(0, (Date.now() - d.getTime()) / 1000);
  }
  function fmtMin(s) { if (s == null) return '?'; return s >= 90 ? `${Math.round(s / 60)} min` : `${Math.round(s)} s`; }
  function methodOf(j) { const m = S.methods && S.methods.methods ? S.methods.methods.find((x) => x.id === (j.method || (j.spec && j.spec.method))) : null; return m; }
  function methodName(j) { const m = methodOf(j); return m ? m.name : (j.method || (j.spec && j.spec.method) || j.kind); }
  function jobsFor(kind, id, code) { return S.jobs.filter((j) => j.target && j.target.id === id && (!code || j.target.code === code) && (!kind || !j.target.kind || j.target.kind === kind || (kind === 'enemy' && j.target.kind === 'boss') || (kind === 'boss' && j.target.kind === 'enemy'))); }

  async function post(url, body) {
    const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) });
    let res;
    try { res = await r.json(); } catch (_) { res = { ok: false, error: `HTTP ${r.status}` }; }
    if (!r.ok && res.ok !== false) res.ok = false;
    if (!res.ok && !res.error) res.error = `HTTP ${r.status}`;
    return res;
  }

  async function act(j, path, body, busyText) {
    App.status(`${title(j)}: ${busyText || path}…`, 'busy');
    const res = await post(`/api/jobs/${encodeURIComponent(j.id)}/${path}`, body);
    if (!res.ok) { App.status(`${title(j)}: ${path} refused: ${res.error}`, 'bad', res.output || ''); return res; }
    App.status(`${title(j)}: ${path} done`, 'good');
    await poll();
    return res;
  }

  function openAsset(t) {
    if (!t || !t.kind || !t.id) return;
    const tab = TAB_OF_KIND[t.kind] || 'items';
    if (typeof Assets !== 'undefined' && typeof Assets.open === 'function') {
      try { Assets.open(t.kind, t.id); } catch (e) { App.status(`could not open ${t.id}: ${e.message}`, 'bad'); }
    }
    App.switchTab(tab);
    if (t.code && typeof LookGrid !== 'undefined') setTimeout(() => LookGrid.select(t.code, t.kind, t.id), 50);
  }

  function methods() {
    if (typeof Assets !== 'undefined' && Assets.S && Assets.S.methods && Assets.S.methods.methods) { S.methods = Assets.S.methods; return Promise.resolve(S.methods); }
    if (S.methodsP) return S.methodsP;
    S.methodsP = fetch('/api/methods', { cache: 'no-store' }).then((r) => (r.ok ? r.json() : { methods: [] })).catch(() => ({ methods: [] })).then((m) => {
      if (!m || !Array.isArray(m.methods)) m = { methods: [] };
      S.methods = m;
      return m;
    });
    return S.methodsP;
  }
  async function fetchJson(url, dflt) { try { const r = await fetch(url, { cache: 'no-store' }); if (!r.ok) return dflt; return await r.json(); } catch (_) { return dflt; } }
  async function fetchDrivers() { S.drivers = await fetchJson('/api/drivers', []); if (!Array.isArray(S.drivers)) S.drivers = S.drivers.drivers || []; return S.drivers; }
  async function fetchRefs() { S.refs = await fetchJson('/api/refs', { '2d': [], '3d': [] }); return S.refs; }
  /** The list record of a target (name, looks): lane P's lists when present, else the list routes. */
  async function recordFor(kind, id) {
    const listKind = kind === 'hero' ? 'heroes' : (kind === 'enemy' || kind === 'boss') ? 'enemies' : 'items';
    let list = typeof Assets !== 'undefined' && Assets.S && Assets.S.lists ? Assets.S.lists[listKind] : null;
    if (!list) {
      if (!S.lists[listKind] || Date.now() - S.lists[listKind].at > 15000) S.lists[listKind] = { at: Date.now(), p: fetchJson(`/api/${listKind}`, null) };
      list = await S.lists[listKind].p;
    }
    if (!list) return null;
    if (Array.isArray(list)) return list.find((x) => x.id === id) || null;
    for (const k of ['weapons', 'lines', 'passives', 'quests']) {
      const hit = (list[k] || []).find((x) => x.id === id);
      if (hit) return hit;
      for (const w of list[k] || []) {
        if (w.evolution && w.evolution.id === id) return w.evolution;
        const m = (w.mutations || []).find((x) => x.id === id);
        if (m) return m;
        if (w.evolved && w.evolved.id === id) return w.evolved;
      }
    }
    return null;
  }

  // ------------------------------------------------------------------ the tab

  function render(panel) {
    S.panel = panel;
    clear(panel);
    const root = el('div', { class: 'jobs' });
    panel.appendChild(root);
    const head = el('div', { class: 'jobs-head' });
    head.appendChild(el('h1', { text: 'Jobs' }));
    head.appendChild(el('span', { class: 'muted small', text: 'the local AI\'s queue: one ComfyUI job and one Godot process at a time (tools/dl/locks/); this page asks every 2 s' }));
    head.appendChild(el('span', { class: 'spacer' }));
    head.appendChild(el('button', { type: 'button', class: 'btn small', text: 'Clear finished', title: 'delete the records of every done, failed, interrupted and cancelled job (their folders under tools/dl/jobs/ go too; the painted files stay where the tools put them)', onclick: () => { S.confirm = 'clear'; drawHeader(); } }));
    head.appendChild(el('button', { type: 'button', class: 'btn small', text: 'Refresh', onclick: () => { S.rev = 0; poll(); } }));
    root.appendChild(head);
    root.appendChild(el('div', { class: 'jobs-status', id: 'jobs-status' }));
    root.appendChild(el('div', { id: 'jobs-confirm' }));
    S.groups = el('div', { class: 'jobs-groups' });
    root.appendChild(S.groups);
    for (const c of S.cards.values()) disposeCard(c);
    S.cards.clear(); S.sigs.clear();
    drawHeader();
    draw();
    methods().then(() => { if (App.S.tab === 'jobs' && S.panel === panel && panel.isConnected) { S.sigs.clear(); draw(); } });
    if (Date.now() - S.statusAt > 4000) fetchStatus().then(() => { if (panel.isConnected) drawHeader(); });
    poll();
  }

  function drawHeader() {
    const box = document.getElementById('jobs-status');
    if (!box) return;
    clear(box);
    if (S.apiMissing) {
      box.appendChild(el('span', { class: 'warn-text', text: `the jobs API is not here yet${S.apiError ? ' (' + S.apiError + ')' : ''}: the server (tools/level_editor/server.py) needs lane S's routes and lane J's jobs.py; this page asks again every 15 s` }));
    }
    const st = S.status || {};
    const locks = st.locks || {};
    const lock = (name, label) => {
      const o = locks[name];
      const w = el('span', { class: 'lock' });
      if (!o) { w.append(el('i', { class: 'dot' }), el('span', { text: `${label}: free` })); return w; }
      const age = fmtT(o.age_s || 0);
      if (o.owner_file === false || !o.who || o.who === 'unknown process') {
        w.append(el('i', { class: 'dot unknown' }), el('span', { text: `${label}: held by an unknown process for ${age}`, title: 'a lock folder without owner.json (a bare mkdir lock): the code never reclaims it' }));
        w.appendChild(el('button', { type: 'button', class: 'btn small danger', text: S.confirm === 'force:' + name ? 'Really force release?' : 'Force release', title: 'remove the lock folder although nobody owns it: only when you know no Godot / ComfyUI job of yours is running', onclick: async () => {
          if (S.confirm !== 'force:' + name) { S.confirm = 'force:' + name; drawHeader(); return; }
          S.confirm = null;
          const res = await post(`/api/locks/${name}/release`, { force: true });
          App.status(res.ok ? `${label} lock released` : `${label}: ${res.error}`, res.ok ? 'good' : 'bad');
          await fetchStatus(); drawHeader();
        } }));
        return w;
      }
      const dead = o.alive === false;
      w.append(el('i', { class: 'dot held' }), el('span', { text: `${label}: held by ${o.who}${o.job ? ' (' + o.job + ')' : ''} for ${age}${dead ? ' · its process is gone: reclaimed on the next acquire' : ''}`, title: o.note || '' }));
      return w;
    };
    box.appendChild(lock('comfy', 'ComfyUI'));
    box.appendChild(lock('godot', 'Godot'));
    box.appendChild(el('span', { class: 'lock' }, el('i', { class: 'dot ' + (st.blender ? '' : 'off') }), el('span', { text: `Blender: ${st.blender ? 'found' : 'not found'}`, title: st.blender || 'driver and reference jobs need Blender: env BLENDER, %LOCALAPPDATA%/Programs/blender-*/blender.exe or C:/Program Files/Blender Foundation/Blender */blender.exe' })));
    box.appendChild(el('span', { class: 'lock' }, el('i', { class: 'dot ' + (st.qa_online ? '' : st.qa_online === false ? 'off' : 'off') }), el('span', { text: `QA ${st.qa_online ? 'online' : st.qa_online === false ? 'offline' : 'unknown'}`, title: 'the vision check (LM Studio) that counts subjects, legs and views on every still; offline, the tools keep every first roll' })));
    const jst = st.jobs || {};
    if (jst.lanes) box.appendChild(el('span', { class: 'muted', text: 'lanes: ' + Object.entries(jst.lanes).map(([k, v]) => `${k} ${v ? '#' + shortId(v) : 'idle'}`).join(' · '), title: 'comfy: the art; godot: register / import / launch; local: Blender, pose tools, recolour, install' }));
    const c = document.getElementById('jobs-confirm');
    if (c) {
      clear(c);
      if (S.confirm === 'clear') {
        const fin = S.jobs.filter((j) => FINISHED.includes(j.state));
        c.appendChild(el('div', { class: 'lg-confirm' },
          el('span', { text: `Delete the ${fin.length} finished job record${fin.length === 1 ? '' : 's'}? The painted files stay; only the records and their folders under tools/dl/jobs/ go.` }),
          el('button', { type: 'button', class: 'btn small danger', text: 'Yes, clear', disabled: !fin.length, onclick: async () => { S.confirm = null; for (const j of fin) await post(`/api/jobs/${encodeURIComponent(j.id)}/delete`, {}); S.hidden.clear(); await poll(); drawHeader(); } }),
          el('button', { type: 'button', class: 'btn small ghost', text: 'Cancel', onclick: () => { S.confirm = null; drawHeader(); } })));
      }
    }
  }

  function sig(j) {
    const p = j.progress || {};
    return JSON.stringify([j.state, j.waiting_for, p.stage, p.done, p.total, p.stalled, (j.log_tail || []).slice(-1)[0], (j.outputs || []).length, (j.choices || []).length, j.ended, j.error, j.written && j.written.layout, j.merged_into, j.eta_s, j.state === 'running' ? Math.floor(Date.now() / 2000) : 0, S.hidden.has(j.id)]);
  }

  function draw() {
    if (!S.groups) return;
    clear(S.groups);
    const jobs = S.jobs.filter((j) => !S.hidden.has(j.id));
    if (!jobs.length) {
      S.groups.appendChild(el('div', { class: 'jempty' }, el('div', { text: S.apiMissing ? 'no jobs API yet' : 'no jobs' }), el('div', { class: 'small', text: 'Queue one from a creature\'s or a hero\'s Looks (+ New look…, Re-roll…, Icon candidates…), an item\'s icon, or a hero\'s badge and title cut-out.' })));
      return;
    }
    const by = { running: [], waiting: [], queued: [], finished: [] };
    for (const j of jobs) (by[j.state] || by.finished).push(j);
    by.queued.sort((a, b) => (a.lane || '').localeCompare(b.lane || '') || String(a.created || '').localeCompare(String(b.created || '')));
    by.finished.sort((a, b) => String(b.ended || b.created || '').localeCompare(String(a.ended || a.created || '')));
    for (const [key, label] of GROUPS) {
      const list = by[key];
      if (!list.length) continue;
      const g = el('div', { class: 'jobs-group' }, el('h2', { text: `${label} · ${list.length}` }));
      list.forEach((j, i) => {
        const s = sig(j);
        let c = S.cards.get(j.id);
        if (!c || S.sigs.get(j.id) !== s || c.dataset.pos !== String(i)) {
          if (c) disposeCard(c);        // the old card's clip players go with it (a running card is rebuilt every poll)
          c = card(j, i, list.length); c.dataset.pos = String(i); S.cards.set(j.id, c); S.sigs.set(j.id, s);
        }
        g.appendChild(c);
      });
      S.groups.appendChild(g);
    }
    for (const id of [...S.cards.keys()]) if (!jobs.some((j) => j.id === id)) { disposeCard(S.cards.get(id)); S.cards.delete(id); S.sigs.delete(id); }
  }

  function disposeCard(c) { for (const p of (c && c.__players) || []) p.destroy(); if (c) c.__players = []; }

  // ------------------------------------------------------------------ the cards

  function card(j, pos, n) {
    const t = j.target || {};
    const c = el('article', { class: `jcard state-${j.state}`, 'data-id': j.id });
    c.__players = [];
    const head = el('div', { class: 'jcard-head' },
      el('span', { class: `chip state-${j.state}`, text: STATE_LABEL[j.state] || j.state }),
      el('span', { class: 'jid', text: '#' + shortId(j.id), title: j.id }),
      el('span', { class: 'jtitle', text: title(j) }));
    const times = [];
    if (j.created) times.push('created ' + when(j.created));
    if (j.started) times.push('started ' + when(j.started));
    if (j.ended) times.push('ended ' + when(j.ended));
    head.appendChild(el('span', { class: 'jwhen', text: times.join(' · ') }));
    c.appendChild(head);
    const sub = el('div', { class: 'jcard-sub' });
    if (t.kind) sub.appendChild(el('span', {}, el('span', { class: 'muted', text: 'target ' }), el('b', { text: `${t.kind} ${t.id || ''}${t.code ? ' · ' + t.code : ''}` })));
    sub.appendChild(el('span', {}, el('span', { class: 'muted', text: 'method ' }), el('span', { text: methodName(j), title: j.method || '' })));
    if (j.lane) sub.appendChild(el('span', { class: 'muted', text: `lane ${j.lane}` }));
    if (j.phase > 1 || j.attempt > 1) sub.appendChild(el('span', { class: 'muted', text: `phase ${j.phase || 1} · attempt ${j.attempt || 1}` }));
    if (j.spec && j.spec.note) sub.appendChild(el('span', { class: 'muted', text: '“' + j.spec.note + '”' }));
    if (j.qa_online === false) sub.appendChild(el('span', { class: 'warn-text', text: 'QA offline: every first roll kept', title: 'the vision check did not answer; the tools keep what the model painted first' }));
    c.appendChild(sub);
    if (j.state === 'running') runningBody(c, j);
    else if (j.state === 'waiting') waitingBody(c, j);
    else if (j.state === 'queued') queuedBody(c, j, pos, n);
    else if (j.state === 'done') doneBody(c, j);
    else failedBody(c, j);
    if (j.equiv) c.appendChild(el('details', { class: 'jfold' }, el('summary', { text: 'the command Claude would type' }), el('div', { class: 'jequiv', text: j.equiv })));
    if (j.spec) c.appendChild(el('details', { class: 'jfold' }, el('summary', { text: 'the spec' }), el('pre', { class: 'jlog', text: JSON.stringify(j.spec, null, 1) })));
    return c;
  }

  function stagesRow(j) {
    const p = j.progress || {};
    const row = el('div', { class: 'jstages' });
    for (const s of p.stages || []) row.appendChild(el('span', { class: 'jstage ' + (s.state || ''), text: s.name + (s.secs ? ` ${Math.round(s.secs)}s` : ''), title: `${s.name}: ${s.state || 'pending'}` }));
    return row;
  }

  function logTail(j, lines) {
    const tail = (j.log_tail || []).slice(-(lines || LOG_LINES));
    const pre = el('pre', { class: 'jlog', text: tail.join('\n') || '(no output yet)' });
    requestAnimationFrame(() => { pre.scrollTop = pre.scrollHeight; });
    return pre;
  }

  function runningBody(c, j) {
    const p = j.progress || {};
    const elapsed = secondsSince(j.started);
    const eta = j.eta_s != null ? ` / ~${fmtT(j.eta_s)}` : '';
    c.appendChild(el('div', { class: 'jcard-sub' },
      el('span', {}, el('span', { class: 'muted', text: 'stage ' }), el('b', { text: p.stage || '…' }), el('span', { class: 'muted', text: p.total ? ` (${p.done || 0} of ${p.total})` : '' })),
      el('span', {}, el('span', { class: 'muted', text: 'elapsed ' }), el('span', { text: fmtT(elapsed) + eta, title: 'the estimate ("~") is the method\'s measured median × its stages; a Flux.2 dev restart can add minutes' })),
      p.stalled ? el('span', { class: 'warn-text', text: 'no output for 20 min: stalled? (never killed on its own; Cancel if you are sure)' }) : null,
      j.lock_waits && Object.keys(j.lock_waits).length ? el('span', { class: 'warn-text', text: 'waiting for a lock: ' + Object.entries(j.lock_waits).map(([k, v]) => `${k} ${v}`).join('; ') }) : null,
      p.last_output ? el('span', { class: 'muted', text: p.last_output, title: 'the last line the tool printed' }) : null));
    if (p.total) c.appendChild(el('div', { class: 'jbar' + (p.stalled ? ' stalled' : '') }, el('i', { style: `width:${Math.min(100, Math.round(100 * (p.done || 0) / p.total))}%` })));
    if (p.stages && p.stages.length) c.appendChild(stagesRow(j));
    c.appendChild(logTail(j));
    if (j.outputs && j.outputs.length) c.appendChild(outputs(j, c.__players));
    c.appendChild(el('div', { class: 'jcard-actions' },
      el('button', { type: 'button', class: 'btn small danger', text: 'Cancel', title: 'kill the tool (and, for a ComfyUI job, interrupt the server\'s queue, which holds only ours under the lock)', onclick: () => act(j, 'cancel', {}, 'cancelling') }),
      j.target && j.target.id ? el('button', { type: 'button', class: 'btn small', text: 'Open asset', onclick: () => openAsset(j.target) }) : null,
      el('button', { type: 'button', class: 'btn small ghost', text: 'Log', title: 'the last 80 lines', onclick: () => showLog(j) })));
  }

  function waitingBody(c, j) {
    const choices = j.choices || [];
    let picked = c.__picked || null;
    const what = { side: 'the side painting the other views follow', view: 'one view\'s candidates', pick: 'a candidate' }[j.waiting_for] || 'a candidate';
    c.appendChild(el('div', { class: 'jcard-sub' }, el('b', { text: `needs your pick: ${what} (${choices.length} candidate${choices.length === 1 ? '' : 's'})` }), el('span', { class: 'muted', text: j.progress && j.progress.stage ? j.progress.stage : '' }), el('span', { class: 'muted', text: 'click a picture to zoom, click the card to choose' })));
    const grid = el('div', { class: 'jchoices' });
    const pickBtn = el('button', { type: 'button', class: 'btn small primary', text: 'Pick', disabled: true, onclick: () => act(j, 'pick', { choice: picked }, `picking ${picked}`) });
    for (const ch of choices) {
      const key = ch.key != null ? ch.key : ch.label;
      const box = el('div', { class: 'jchoice' + (picked === key ? ' picked' : ''), title: ch.label || key });
      const img = el('img', { src: ch.url, alt: '', loading: 'lazy' });
      img.addEventListener('click', (e) => { e.stopPropagation(); StripPlayer.openImage(ch.url, `${title(j)} · ${ch.label || key}`); });
      box.appendChild(img);
      box.appendChild(el('span', { text: ch.label || key }));
      if (ch.qa && ch.qa.problems && ch.qa.problems.length) box.appendChild(el('span', { class: 'qa-bad', text: 'QA: ' + ch.qa.problems.join(', ') }));
      box.addEventListener('click', () => { picked = key; c.__picked = key; for (const x of grid.children) x.classList.toggle('picked', x === box); pickBtn.disabled = false; pickBtn.textContent = `Pick ${ch.label || key}`; });
      grid.appendChild(box);
    }
    c.appendChild(grid);
    const sheet = choices.find((ch) => ch.sheet);
    if (sheet) c.appendChild(el('div', { class: 'muted small' }, el('a', { href: '#', text: 'the review sheet', onclick: (e) => { e.preventDefault(); StripPlayer.openImage(sheet.sheet, 'the review sheet'); } })));
    const n = (j.spec && j.spec.counts && j.spec.counts.seeds) || choices.length || 3;
    c.appendChild(el('div', { class: 'jcard-actions' },
      pickBtn,
      el('button', { type: 'button', class: 'btn small', text: `Re-roll ${n} more`, title: 'the same stage again with the next seeds: new candidates', onclick: () => act(j, 'requeue', { reroll: { stills: choices.map((ch) => ch.cache_key).filter(Boolean), clips: [], seed: seedOf(j) + 1 } }, 're-rolling') }),
      el('button', { type: 'button', class: 'btn small danger', text: 'Cancel', onclick: () => act(j, 'cancel', {}, 'cancelling') }),
      el('button', { type: 'button', class: 'btn small ghost', text: 'Edit', title: 'change the spec: the job goes back to the queue at phase 1 (its candidates are stale)', onclick: () => openForm(j.target.kind, j.target.id, { job: j }) })));
  }

  function queuedBody(c, j, pos, n) {
    c.appendChild(el('div', { class: 'jcard-sub' },
      el('span', { class: 'muted', text: `#${pos + 1} of ${n} queued${j.lane ? ' · the ' + j.lane + ' lane' : ''}` }),
      j.eta_s != null ? el('span', { class: 'muted', text: `~${fmtT(j.eta_s)} once it runs`, title: 'the method\'s measured median × its stages' }) : null));
    c.appendChild(el('div', { class: 'jcard-actions' },
      el('button', { type: 'button', class: 'btn small', text: 'Edit', title: 'change the spec in the form', onclick: () => openForm(j.target.kind, j.target.id, { job: j }) }),
      el('button', { type: 'button', class: 'btn small', text: '▲', title: 'earlier in its lane', disabled: pos === 0, onclick: () => act(j, 'move', { delta: -1 }, 'moving') }),
      el('button', { type: 'button', class: 'btn small', text: '▼', title: 'later in its lane', disabled: pos >= n - 1, onclick: () => act(j, 'move', { delta: 1 }, 'moving') }),
      el('button', { type: 'button', class: 'btn small danger', text: 'Cancel', onclick: () => act(j, 'cancel', {}, 'cancelling') })));
  }

  function doneBody(c, j) {
    const w = j.written;
    if (w && w.file) {
      const layout = w.layout || '';
      const text = layout === 'unmerged' ? 'the result is NOT in the JSON yet' : `wrote ${w.file.split(/[\\/]/).pop()}${w.keys && w.keys.length ? ' (' + w.keys.join(', ') + ')' : ''} · ${layout === 'block' ? 'the whole variants block rewritten in place' : layout === 'entry' ? 'one entry written in place' : layout === 'redumped' ? 'RE-DUMPED (the file\'s layout changed)' : layout}${w.backup ? ' · backup ' + String(w.backup).split(/[\\/]/).pop() : ''}`;
      c.appendChild(el('div', { class: layout === 'unmerged' ? 'jwarn' : 'jcard-sub muted', text }));
      if (layout === 'unmerged') c.appendChild(el('div', { class: 'jwarn' },
        el('span', { text: 'Neither the block write nor the entry write fit this file\'s layout (a hand-edited JSON). The strip, the icon and result.json are on disk. Choose:' }),
        el('button', { type: 'button', class: 'btn small', text: 'Merge again', title: 'try the line-preserving merge once more (after you tidied the file, say)', onclick: () => act(j, 'merge', { redump: false }, 'merging') }),
        el('button', { type: 'button', class: 'btn small danger', text: 'Re-dump this file (changes its layout)', title: 'write the whole JSON again with a two-space indent: every line may change in git, but the look lands', onclick: () => act(j, 'merge', { redump: true }, 're-dumping') })));
    }
    if (j.outputs && j.outputs.length) c.appendChild(outputs(j, c.__players));
    if (j.choices && j.choices.length) installChoices(c, j);
    if (j.progress && j.progress.stages && j.progress.stages.length) c.appendChild(stagesRow(j));
    c.appendChild(el('div', { class: 'jcard-actions' },
      j.target && j.target.id ? el('button', { type: 'button', class: 'btn small primary', text: j.target.code ? 'Open look' : 'Open asset', onclick: () => openAsset(j.target) }) : null,
      el('button', { type: 'button', class: 'btn small', text: 'Re-queue', title: 'the same spec again (attempt + 1); the tools reuse what is cached unless you re-roll', onclick: () => act(j, 'requeue', {}, 're-queueing') }),
      el('button', { type: 'button', class: 'btn small', text: 'Re-roll…', title: 'choose which cached stills and clips to throw away, then re-queue', onclick: () => rerollPanel(c, j) }),
      el('button', { type: 'button', class: 'btn small ghost', text: 'Hide', title: 'hide this card until the page reloads', onclick: () => { S.hidden.add(j.id); draw(); } }),
      el('button', { type: 'button', class: 'btn small ghost', text: 'Log', onclick: () => showLog(j) }),
      el('span', { class: 'spacer' }),
      el('button', { type: 'button', class: 'btn small ghost danger', text: 'Delete', title: 'remove the record and tools/dl/jobs/<id>/', onclick: () => act(j, 'delete', {}, 'deleting') })));
  }

  function installChoices(c, j) {
    const choices = j.choices || [];
    let picked = null;
    c.appendChild(el('div', { class: 'jcard-sub' }, el('b', { text: `${choices.length} candidates to pick from` }), el('span', { class: 'muted', text: 'Install writes the picked one into the content (the old file is backed up) and imports it' })));
    const grid = el('div', { class: 'jchoices' });
    const btn = el('button', { type: 'button', class: 'btn small primary', text: 'Install', disabled: true, onclick: () => act(j, 'install', { choice: picked }, `installing ${picked}`) });
    for (const ch of choices) {
      const key = ch.key != null ? ch.key : ch.label;
      const box = el('div', { class: 'jchoice', title: ch.label || key });
      const img = el('img', { src: ch.url, alt: '', loading: 'lazy' });
      img.addEventListener('click', (e) => { e.stopPropagation(); StripPlayer.openImage(ch.url, `${title(j)} · ${ch.label || key}`); });
      box.append(img, el('span', { text: ch.label || key }));
      box.addEventListener('click', () => { picked = key; for (const x of grid.children) x.classList.toggle('picked', x === box); btn.disabled = false; btn.textContent = `Install ${ch.label || key}`; });
      grid.appendChild(box);
    }
    c.appendChild(grid);
    c.appendChild(el('div', { class: 'jcard-actions' }, btn, el('button', { type: 'button', class: 'btn small', text: `Re-roll ${choices.length} more`, onclick: () => act(j, 'requeue', { reroll: { seed: ((j.spec && j.spec.flags && j.spec.flags.seed) || 0) + 1 } }, 're-rolling') })));
  }

  function failedBody(c, j) {
    if (j.error) c.appendChild(el('div', { class: 'jerror', text: j.error }));
    else if (j.state === 'interrupted') c.appendChild(el('div', { class: 'jwarn', text: 'The server restarted while this job ran: its process was stopped. Re-queue continues from the tools\' caches (finished stills and clips are reused).' }));
    else if (j.state === 'cancelled') c.appendChild(el('div', { class: 'muted small', text: 'cancelled' }));
    if (j.log_tail && j.log_tail.length) c.appendChild(logTail(j, 6));
    const t = j.target || {};
    c.appendChild(el('div', { class: 'jcard-actions' },
      el('button', { type: 'button', class: 'btn small primary', text: 'Re-queue', onclick: () => act(j, 'requeue', {}, 're-queueing') }),
      el('button', { type: 'button', class: 'btn small', text: 'Re-roll…', title: 'choose which cached stills and clips to throw away, then re-queue', onclick: () => rerollPanel(c, j) }),
      el('button', { type: 'button', class: 'btn small', text: 'Edit', onclick: () => openForm(t.kind, t.id, { job: j }) }),
      el('button', { type: 'button', class: 'btn small ghost', text: 'Log', onclick: () => showLog(j) }),
      j.kind === 'look' && t.code ? el('button', { type: 'button', class: 'btn small ghost', text: 'Remove the stub', title: `delete variants["${t.code}"] from ${t.id}.json when it has no strip (the server refuses otherwise)`, onclick: async () => {
        const res = await post(`/api/content/${encodeURIComponent(t.kind)}/${encodeURIComponent(t.id)}/look/${encodeURIComponent(t.code)}`, { op: 'remove' });
        App.status(res.ok ? `${t.id}: the stub ${t.code} is gone` : `${t.id} ${t.code}: ${res.error}`, res.ok ? 'good' : 'bad');
      } }) : null,
      el('span', { class: 'spacer' }),
      el('button', { type: 'button', class: 'btn small ghost danger', text: 'Delete', onclick: () => act(j, 'delete', {}, 'deleting') })));
  }

  /** Re-queue with a re-roll: the record's cache_keys (stills, clips) as boxes to tick and the next seed. */
  function rerollPanel(c, j) {
    const old = c.querySelector('.jreroll');
    if (old) { old.remove(); return; }
    const ck = j.cache_keys || {};
    const stills = Array.isArray(ck.stills) ? ck.stills : [], clips = Array.isArray(ck.clips) ? ck.clips : [];
    const box = el('div', { class: 'lg-edit jreroll' });
    box.appendChild(el('b', { text: 'Re-queue with a re-roll: what to throw away' }));
    const picks = { stills: new Set(), clips: new Set() };
    for (const [label, list, set, note] of [['stills', stills, picks.stills, 'copied to <key>_old<stamp> and painted again'], ['clips', clips, picks.clips, 'the folder moves to <key>_old<stamp> and the walk is made again']]) {
      if (!list.length) continue;
      const row = el('div', { class: 'row' }, el('span', { class: 'muted small', text: `${label} (${note}):` }));
      for (const k of list) { const cb = el('input', { type: 'checkbox' }); cb.addEventListener('change', () => { if (cb.checked) set.add(k); else set.delete(k); }); row.appendChild(el('label', { class: 'cb' }, cb, el('span', { text: k }))); }
      const all = el('button', { type: 'button', class: 'btn small ghost', text: 'all', onclick: () => { for (const cb of row.querySelectorAll('input')) { cb.checked = true; } for (const k of list) set.add(k); } });
      row.appendChild(all);
      box.appendChild(row);
    }
    if (!stills.length && !clips.length) box.appendChild(el('div', { class: 'muted small', text: 'this job lists no cached keys: a re-queue with the next seed rolls everything again' }));
    const seedCb = el('input', { type: 'checkbox' }); seedCb.checked = true;
    box.appendChild(el('label', { class: 'cb' }, seedCb, el('span', { text: `the next seed (${seedOf(j)} → ${seedOf(j) + 1})` })));
    box.appendChild(el('div', { class: 'row' },
      el('button', { type: 'button', class: 'btn small primary', text: 'Re-queue', onclick: () => { const reroll = { stills: [...picks.stills], clips: [...picks.clips] }; if (seedCb.checked) reroll.seed = seedOf(j) + 1; box.remove(); act(j, 'requeue', { reroll }, 're-rolling'); } }),
      el('button', { type: 'button', class: 'btn small ghost', text: 'Cancel', onclick: () => box.remove() })));
    c.appendChild(box);
  }

  /** The job's outputs: stills with their QA verdict, clips played from their out_NN frames, sheets, icons, the strip. */
  function outputs(j, holder) {
    const box = el('div', { class: 'joutputs' });
    const flows = (j.outputs || []).filter((o) => o.type === 'workflow');
    if (flows.length) {
      // the ComfyUI workflows this job ran, one file per render: drag the file into the ComfyUI page to see every node
      const row = el('div', { class: 'jflows' }, el('b', { text: 'ComfyUI workflows' }),
        el('span', { class: 'muted small', text: ' (one per render; save it, then drag it into ' }),
        el('a', { href: COMFY_URL, target: '_blank', rel: 'noopener', text: 'the ComfyUI page' }), el('span', { class: 'muted small', text: ')' }));
      for (const o of flows) row.appendChild(el('a', { class: 'jflow', href: o.url, target: '_blank', rel: 'noopener', text: o.label, title: 'the workflow as the ComfyUI page loads it' }));
      box.appendChild(row);
    }
    for (const o of j.outputs || []) {
      if (o.type === 'workflow') continue;
      const cellEl = el('div', { class: 'joutput' });
      if (o.type === 'clip' && o.url) {
        const n = Number(o.frames) || 12;
        const base = String(o.url).replace(/\/?$/, '/');
        const p = StripPlayer.createSeq({ pattern: base + 'out_%02d.png', count: n, fps: Number(o.fps) || 12, size: 120, mode: 'hover', label: o.label || 'clip' });
        if (holder) holder.push(p);
        cellEl.appendChild(p.el);
      } else if (o.type === 'strip' && o.url) {
        cellEl.appendChild(el('a', { href: '#', text: 'the strip', onclick: (e) => { e.preventDefault(); openAsset(j.target); } }));
      } else if (o.url) {
        const img = el('img', { src: o.url, alt: '', loading: 'lazy', title: o.label || '' });
        img.addEventListener('click', () => StripPlayer.openImage(o.url, `${title(j)} · ${o.label || o.type}`));
        cellEl.appendChild(img);
      }
      cellEl.appendChild(el('span', { text: o.label || o.type || '' }));
      if (o.clip_kind) cellEl.appendChild(el('span', { class: o.clip_kind === 'free' || o.clip_kind === 'procedural' ? 'qa-bad' : 'muted', text: o.clip_kind + (o.clip_kind === 'free' ? ' (fell back from the driver)' : ''), title: 'how the clip was made: pose (a driver), control (a depth video), free (Wan guessed), procedural (no video)' }));
      if (o.qa && o.qa.problems && o.qa.problems.length) cellEl.appendChild(el('span', { class: 'qa-bad', text: 'QA: ' + o.qa.problems.join(', ') }));
      else if (o.qa) cellEl.appendChild(el('span', { class: 'muted', text: 'QA ok' }));
      box.appendChild(cellEl);
    }
    return box;
  }

  async function showLog(j) {
    const full = await fetchJson(`/api/job/${encodeURIComponent(j.id)}`, null);
    const rec = full && full.job ? full.job : full || j;
    const dlg = document.createElement('dialog');
    dlg.className = 'sp-modal';
    dlg.append(
      el('div', { class: 'sp-modal-head' }, el('b', { text: `${title(j)} · log` }), el('span', { class: 'muted small', text: rec.log_file || '' }), el('span', { class: 'spacer' }), el('button', { type: 'button', class: 'btn small', text: '✕ close', onclick: () => dlg.close() })),
      el('pre', { class: 'jlog', style: 'max-height: 70vh; min-width: 600px;', text: (rec.log_tail || []).join('\n') || '(nothing logged)' }));
    document.body.appendChild(dlg);
    dlg.addEventListener('close', () => dlg.remove());
    dlg.showModal();
  }

  // ------------------------------------------------------------------ the job form

  function modeOfMethod(m) {
    if (Array.isArray(m.modes) && m.modes.length) return m.modes;
    const id = m.id || '';
    if (id.startsWith('driver_') || id.startsWith('ref_')) return ['driver'];
    if (id === 'icon_cands' || id === 'item_icon') return ['icon'];
    if (id === 'hero_badge') return ['badge'];
    if (id === 'hero_title') return ['title'];
    return ['look'];
  }
  function kindClass(kind) { return kind === 'hero' ? 'hero' : (kind === 'enemy' || kind === 'boss') ? 'enemy' : 'item'; }
  /** The methods that fit a target and a mode: methods.json's `kinds` (icon_cands: item, enemy, hero) or `kind` (enemy,
   *  hero, item, driver, ref); the driver / ref tools fit every target. */
  function methodsFor(all, kind, mode) {
    const kc = kindClass(kind);
    const kinds = (m) => (Array.isArray(m.kinds) && m.kinds.length ? m.kinds : [m.kind || 'any']);
    return all.filter((m) => modeOfMethod(m).includes(mode) && (mode === 'driver' || kinds(m).includes('any') || kinds(m).includes(kc)));
  }
  function jobKind(mode, method, kind) {
    if (mode === 'look') return 'look';
    if (mode === 'icon') return method && method.id === 'item_icon' ? 'item_icon' : 'icon_cands';
    if (mode === 'badge') return 'hero_badge';
    if (mode === 'title') return 'hero_title';
    return method ? method.id : 'driver_pose';
  }
  function ordinal(n) { return ['first', 'second', 'third', 'fourth', 'fifth', 'sixth', 'seventh', 'eighth'][n - 1] || `${n}th`; }

  /** The next free look codes (INTERFACES §3): the most common prefix of the codes, else variant_base's, else the id's
   *  initials (a one-word id takes three letters); A..Z then AA..; a code in use is skipped. */
  function nextCodes(record, n, existing) {
    if (typeof AssetsModel !== 'undefined' && typeof AssetsModel.nextCodes === 'function') { try { return AssetsModel.nextCodes(record, n); } catch (_) { /* fall through */ } }
    const codes = (existing || []).map(String);
    const counts = {};
    for (const c of codes) { const p = c.includes('-') ? c.split('-').slice(0, -1).join('-') : ''; if (p) counts[p] = (counts[p] || 0) + 1; }
    let prefix = Object.keys(counts).sort((a, b) => counts[b] - counts[a] || a.localeCompare(b))[0];
    if (!prefix && record && record.variant_base && String(record.variant_base).includes('-')) prefix = String(record.variant_base).split('-').slice(0, -1).join('-');
    if (!prefix) { const words = String(record && record.id || 'x').split('_'); prefix = words.length > 1 ? words.map((w) => w[0]).join('').toUpperCase() : words[0].slice(0, 3).toUpperCase(); }
    const used = new Set(codes);
    const out = [];
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    for (let i = 0; out.length < n && i < 26 * 27; i++) {
      const suf = i < 26 ? letters[i] : letters[Math.floor(i / 26) - 1] + letters[i % 26];
      const code = `${prefix}-${suf}`;
      if (!used.has(code)) { out.push(code); used.add(code); }
    }
    return out;
  }

  /** The words the pipeline will send, composed from methods.json's wordings and the fields (the authoritative check is
   *  asset_job.py --dry-run on the job card). */
  function composeWords(m, method, spec, target) {
    const w = (m && Array.isArray(m.ref_wordings)) ? m.ref_wordings : [];
    const r = spec.recipe || {};
    const find = (role, level) => w.find((x) => x.role === role && (!level || x.level === level)) || w.find((x) => x.role === role);
    const sub = (text, n) => String(text || '')
      .replace(/<n>th/g, ordinal(n)).replace(/<n>/g, String(n))
      .replace(/<subject>|<prompt>/g, r.prompt || r.art_prompt || target.art_prompt || `(the ${target.kind} ${target.id}'s art_prompt: none in its JSON)`)
      .replace(/<keep>/g, r.keep || '(keep: not set)').replace(/<noun>/g, r.noun || target.id.replace(/_/g, ' ')).replace(/<detail>/g, r.detail || '(detail: not set)')
      .replace(/<anatomy>/g, r.anatomy || '(anatomy: not set)').replace(/<blockout>/g, r.blockout || '(blockout: not set)').replace(/<view>/g, 'full body, front view')
      .replace(/<bg>/g, `on a flat ${r.screen || 'green'} screen`).replace(/<STYLE>/g, 'the project\'s style words').replace(/<back_hint>/g, r.back_hint || '')
      .replace(/<object>/g, r.title_holds || r.object || '(the held object)').replace(/<description>/g, (r.title_extra_ref && r.title_extra_ref.words) || r.description || '(what it is)')
      .replace(/<words\[view\]>/g, '(the view\'s words)').replace(/<n>/g, String(n));
    // methods.json's rows: role style (the anchor: fixed | fixed (with other references)), identity (loosely | closely |
    // copy exactly | copy exactly (a figure) | ...), pose (closely | closely (the other views) | loosely (untested)),
    // view (fixed: the turn-arounds), held object, mark; the older draft's names are accepted too
    const lookup = (role, lvl) => w.find((x) => x.role === role && x.level === lvl) || w.find((x) => x.role === role && String(x.level || '').startsWith(lvl)) || find(role);
    const lines = [];
    lines.push(`Method ${method ? method.name : spec.method} · target ${target.kind} ${target.id}${target.code ? ' ' + target.code : ''}`);
    lines.push('');
    lines.push('References, in the order they are passed (Klein takes them as a chain of ReferenceLatent nodes; no strength number exists):');
    let n = 0;
    const others = (spec.refs || []).length > 0;
    if (!(spec.flags && spec.flags.no_style_ref)) {
      n++;
      const anchor = lookup('style', others ? 'fixed (with other references)' : 'fixed') || find('style anchor');
      lines.push(`  ${n}. the style anchor (tools/dl/anchor.png) — ${anchor ? sub(anchor.text, n) : 'Using exactly the same art style, rendering, shading, palette and outline treatment as the reference image, draw a new subject: <subject>. Do not copy any subject from the reference.'}`);
      if (anchor && anchor.source) lines.push(`     (${anchor.source})`);
    }
    for (const ref of spec.refs || []) {
      n++;
      const level = ref.follow === 'copy' ? 'copy exactly' : ref.follow || 'closely';
      const role = ref.role === 'pose' ? 'pose' : ref.role;
      let row = lookup(role, level) || lookup(role === 'pose' ? 'pose-and-anatomy' : role, level);
      if (role === 'pose' && level === 'loosely') row = lookup('pose', 'loosely') || row;
      if (role === 'identity' && level === 'copy exactly' && (ref.use || []).includes('look')) row = lookup('identity', 'copy exactly (a figure)') || row;
      lines.push(`  ${n}. ${ref.path || '(a picture)'} as ${ref.role} · ${level}${ref.use && ref.use.length ? ' · for the ' + ref.use.join(', ') : ''} —`);
      lines.push(`     ${row ? sub(row.text, n) : role === 'style' ? 'the picture goes in after the anchor as a second style reference (no proven wording: the runner adds no words for it)' : '(no proven wording for this role and level in methods.json: the runner passes the picture after the anchor with no extra words)'}`);
      if (row && row.source) lines.push(`     (${row.source})`);
    }
    const turn = lookup('view', 'fixed');
    if (turn) { lines.push(`  the other views are turned from the painting — ${sub(turn.text, n + 1)}`); if (turn.source) lines.push(`     (${turn.source})`); }
    if (spec.drivers && Object.keys(spec.drivers).length) lines.push(`  drivers: ${Object.entries(spec.drivers).map(([k, v]) => `${k} = ${v}`).join(', ')} (OpenPose frames or depth videos steer the clips; a picture never steers motion)`);
    lines.push('');
    lines.push('The subject words:');
    for (const k of ['prompt', 'art_prompt', 'noun', 'keep', 'detail', 'anatomy', 'motion', 'anim_negative', 'back_hint', 'back_prompt', 'dead_hint', 'death', 'stand', 'pose', 'gait', 'directions', 'screen']) if (r[k] != null && r[k] !== '') lines.push(`  ${k}: ${typeof r[k] === 'object' ? JSON.stringify(r[k]) : r[k]}`);
    if (r.words && typeof r.words === 'object') for (const [k, v] of Object.entries(r.words)) lines.push(`  words.${k}: ${v}`);
    if (r.view_hints && typeof r.view_hints === 'object') for (const [k, v] of Object.entries(r.view_hints)) lines.push(`  view_hints.${k}: ${v}`);
    lines.push('');
    if (spec.flags) lines.push(`Flags: ${Object.entries(spec.flags).filter(([, v]) => v).map(([k, v]) => (v === true ? k : `${k}=${v}`)).join(', ') || 'none'}`);
    if (spec.counts) lines.push(`Counts: ${JSON.stringify(spec.counts)}`);
    if (spec.reroll && spec.reroll.mode) lines.push(`Re-roll: ${spec.reroll.mode}${spec.reroll.view ? ' (' + spec.reroll.view + ')' : ''}`);
    lines.push('');
    lines.push(m && m.timings_note ? m.timings_note : '');
    lines.push('What cannot be steered: a picture reaches only the front still (creatures) or the side (gen_ctl); the other views are edits of that painting; motion comes from the driver or Wan\'s guess; the QA counts subjects, legs and views, never likeness. The authoritative words are what tools/asset_job.py --dry-run records on the job card.');
    return lines.join('\n');
  }

  async function openForm(kind, id, o) {
    const opts = o || {};
    const job = opts.job || null;
    const mode = opts.mode || (job ? (modeOfMethod({ id: job.method || (job.spec && job.spec.method) || '' })[0] || 'look') : 'look');
    kind = kind || (job && job.target && job.target.kind) || 'enemy';
    id = id || (job && job.target && job.target.id) || '';
    App.status(`opening the job form for ${id}…`, 'busy');
    const [m, drivers, refs, record, specs, content] = await Promise.all([methods(), fetchDrivers(), fetchRefs(), recordFor(kind, id), fetchSpecs(), fetchJson(`/api/content/${encodeURIComponent(kind)}/${encodeURIComponent(id)}`, null)]);
    const contentJson = content && content.json && typeof content.json === 'object' ? content.json : {};
    App.status('', '');
    const all = m.methods || [];
    const list = methodsFor(all, kind, mode);
    const spec = job && job.spec ? unflatten(job.spec) : { method: opts.method || (list[0] && list[0].id) || '', recipe: opts.recipe ? JSON.parse(JSON.stringify(opts.recipe)) : {}, refs: [], drivers: {}, flags: { skip_qa: false, dev: false, seed: 0 }, counts: { seeds: 3, looks: 1, icon_candidates: 0, cutout_candidates: 0 }, reroll: { mode: opts.reroll ? 'seeds' : '' }, note: '', job: {}, refs3d: [] };
    if (opts.method) spec.method = opts.method;
    if (!spec.recipe) spec.recipe = {};
    if (!spec.refs) spec.refs = [];
    if (!spec.drivers) spec.drivers = {};
    if (!spec.flags) spec.flags = { skip_qa: false, dev: false, seed: 0 };
    if (!spec.counts) spec.counts = { seeds: 3, looks: 1 };
    if (spec.counts.looks == null) spec.counts.looks = 1;
    if (!spec.reroll) spec.reroll = { mode: '' };
    const fixedCode = job ? (job.target && job.target.code) : opts.code || null;
    const looksOf = record ? (record.looks || record.variants || []) : [];
    const existingCodes = looksOf.map((l) => l.code);
    const state = { spec, codes: fixedCode ? [fixedCode] : [], overrides: spec.looks && Array.isArray(spec.looks) ? spec.looks : [], err: '' };
    if (!list.length && !all.length) spec.method = spec.method || '';

    const dlg = document.createElement('dialog');
    dlg.className = 'sp-modal jform';
    const name = record ? (record.name || id) : id;
    const headText = job ? `Edit job #${shortId(job.id)} · ${title(job)}` : `Art job · ${kind} ${name}${fixedCode ? ' · ' + fixedCode : ''} · ${mode === 'look' ? 'looks' : mode === 'icon' ? 'icon candidates' : mode === 'badge' ? 'the round badge' : mode === 'title' ? 'the title cut-out' : 'a 3D driver or reference'}`;
    dlg.appendChild(el('div', { class: 'sp-modal-head' }, el('b', { text: headText }), el('span', { class: 'spacer' }), el('button', { type: 'button', class: 'btn small', text: '✕ close', onclick: () => dlg.close() })));
    const body = el('div');
    dlg.appendChild(body);
    const foot = el('div', { class: 'jform-foot' });
    const err = el('span', { class: 'err' });
    const queueBtn = el('button', { type: 'button', class: 'btn primary', text: job ? 'Save changes' : 'Queue' });
    foot.append(err, el('span', { class: 'spacer' }), el('button', { type: 'button', class: 'btn', text: 'Cancel', onclick: () => dlg.close() }), queueBtn);
    dlg.appendChild(foot);
    document.body.appendChild(dlg);
    dlg.addEventListener('close', () => { for (const p of dlg.__players || []) p.destroy(); dlg.remove(); });
    dlg.__players = [];
    dlg.showModal();

    const draw = () => { clear(body); buildForm(body, dlg, { kind, id, mode, job, m, all, list, drivers, refs, record, state, existingCodes, fixedCode, draw, queueBtn, err, specs, contentJson }); };
    draw();
    queueBtn.addEventListener('click', () => submit({ kind, id, mode, job, m, all, state, fixedCode, dlg, err, queueBtn, record, existingCodes, specs }));
    return dlg;
  }

  function fieldLine(label, control, help) {
    return el('div', { class: 'fieldline' }, el('label', { text: label, title: help || '' }), control, help ? el('div', { class: 'fh', text: help }) : null);
  }

  /** A control for one recipe field of methods.json ({key, type, default, help, options}). */
  function recipeControl(f, value, onChange, ctx) {
    const v = value == null ? '' : value;
    switch (f.type) {
      case 'int': case 'number': {
        const inp = el('input', { type: 'number', class: 'num', value: v, placeholder: f.default != null ? String(f.default) : '', step: f.type === 'int' ? 1 : 'any' });
        inp.addEventListener('change', () => onChange(inp.value === '' ? null : Number(inp.value)));
        return inp;
      }
      case 'bool': {
        const cb = el('input', { type: 'checkbox' }); cb.checked = v === true || (v === '' && f.default === true);
        cb.addEventListener('change', () => onChange(cb.checked));
        return el('label', { class: 'cb' }, cb, el('span', { text: f.help ? '' : 'yes' }));
      }
      case 'select': {
        const sel = el('select');
        if (!f.required) sel.appendChild(el('option', { value: '', text: f.default != null ? `(default: ${f.default})` : '(unset)' }));
        for (const o of f.options || []) { const ov = typeof o === 'object' ? o.v : o; const ol = typeof o === 'object' ? (o.label || o.v) : o; sel.appendChild(el('option', { value: String(ov), text: String(ol), selected: String(ov) === String(v) })); }
        sel.addEventListener('change', () => onChange(sel.value === '' ? null : sel.value));
        return sel;
      }
      case 'textarea': {
        const ta = el('textarea', { placeholder: f.default != null ? String(f.default) : '' });
        ta.value = typeof v === 'object' ? JSON.stringify(v, null, 1) : v;
        ta.addEventListener('change', () => onChange(ta.value.trim() === '' ? null : ta.value));
        return ta;
      }
      case 'view_words': {
        // one line per view (methods.json names them in `views`): {view: words}
        const views = Array.isArray(f.views) && f.views.length ? f.views : Object.keys(f.default && typeof f.default === 'object' ? f.default : { front: '', fd: '', side: '', bd: '', back: '' });
        const obj = v && typeof v === 'object' ? Object.assign({}, v) : {};
        const box = el('div', { class: 'viewwords' });
        for (const view of views) {
          const inp = el('input', { type: 'text', class: 'txt', value: obj[view] || '', placeholder: `${view}: ${f.default && f.default[view] ? f.default[view] : 'words for this view'}` });
          inp.addEventListener('change', () => { if (inp.value.trim()) obj[view] = inp.value.trim(); else delete obj[view]; onChange(Object.keys(obj).length ? obj : null); });
          box.appendChild(el('label', { class: 'vw' }, el('span', { class: 'muted small', text: view }), inp));
        }
        return box;
      }
      case 'json': {
        const ta = el('textarea', { class: 'mono', spellcheck: false, placeholder: f.default != null ? JSON.stringify(f.default) : '{}' });
        ta.value = v === '' ? '' : JSON.stringify(v, null, 1);
        ta.addEventListener('change', () => { try { onChange(ta.value.trim() ? JSON.parse(ta.value) : null); ta.style.borderColor = ''; } catch (_) { ta.style.borderColor = 'var(--s8)'; } });
        return ta;
      }
      case 'driver': {
        const sel = el('select');
        sel.appendChild(el('option', { value: '', text: f.default != null ? `(default: ${f.default})` : '(none)' }));
        for (const d of ctx.drivers || []) sel.appendChild(el('option', { value: d.name, text: `${d.name} (${d.kind || '?'}${d.frames ? ', ' + d.frames + ' frames' : ''})`, selected: d.name === v }));
        if (v && !(ctx.drivers || []).some((d) => d.name === v)) sel.appendChild(el('option', { value: v, text: `${v} (not in the library)`, selected: true }));
        sel.addEventListener('change', () => onChange(sel.value === '' ? null : sel.value));
        return sel;
      }
      case 'file': {
        // a picture (2D uploads) or a model (3D uploads) under tools/dl, with an Upload… button; `src` fields are 3D
        const is3d = /^(src|model|fbx|glb)$/.test(f.key || '');
        const sel = el('select');
        sel.appendChild(el('option', { value: '', text: '(none)' }));
        if (!is3d) for (const r of (ctx.refs && ctx.refs['2d']) || []) sel.appendChild(el('option', { value: r.path || r.url || r.name, text: r.name, selected: (r.path || r.url || r.name) === v }));
        for (const u of (ctx.refs && ctx.refs['3d']) || []) { const p = `tools/dl/uploads/3d/${u.slug}/${u.file || ''}`; sel.appendChild(el('option', { value: p, text: `${u.slug} (${u.file || 'model'})`, selected: p === v })); }
        if (v && ![...sel.options].some((x) => x.value === v)) sel.appendChild(el('option', { value: v, text: v, selected: true }));
        sel.addEventListener('change', () => onChange(sel.value === '' ? null : sel.value));
        const up = el('input', { type: 'file', accept: is3d ? '.fbx,.glb,.gltf,.obj,.dae,.blend,.zip' : '.png,.jpg,.jpeg,.webp', style: 'display:none' });
        up.addEventListener('change', async () => {
          const file = up.files && up.files[0];
          if (!file) return;
          App.status(`uploading ${file.name}…`, 'busy');
          const res = await upload(file, is3d ? '3d' : '2d');
          if (!res.ok) { App.status(`upload failed: ${res.error}`, 'bad'); return; }
          const p = res.path || res.url;
          sel.appendChild(el('option', { value: p, text: file.name, selected: true }));
          onChange(p);
          App.status(`uploaded ${file.name}${is3d ? ': the probe job is queued' : ''}`, 'good');
          fetchRefs();
        });
        return el('span', { class: 'row' }, sel, el('button', { type: 'button', class: 'btn small', text: 'Upload…', onclick: () => up.click() }), up);
      }
      default: {
        const inp = el('input', { type: 'text', class: 'txt', value: typeof v === 'object' ? JSON.stringify(v) : v, placeholder: f.default != null ? String(f.default) : '' });
        inp.addEventListener('change', () => onChange(inp.value.trim() === '' ? null : inp.value.trim()));
        return inp;
      }
    }
  }

  function setKey(obj, key, value) { if (value == null || value === '') delete obj[key]; else obj[key] = value; }

  function buildForm(body, dlg, c) {
    const { kind, id, mode, job, m, all, list, drivers, refs, record, state, existingCodes, fixedCode, draw, specs } = c;
    const spec = state.spec;
    const method = all.find((x) => x.id === spec.method) || list[0] || null;
    if (method && spec.method !== method.id) spec.method = method.id;
    const jk = job ? job.kind : jobKind(mode, method, kind);

    // 1. the method
    body.appendChild(el('h2', {}, 'Method', el('small', { text: m.methods && m.methods.length ? `${list.length} fit a ${kindClass(kind)}'s ${mode}` : 'methods.json is not here yet (lane B): the job runs with the method id typed below' })));
    if (!list.length) {
      const inp = el('input', { type: 'text', class: 'txt', value: spec.method || '', placeholder: 'creature_pose2, hero_fit, creature_ctl, …' });
      inp.addEventListener('change', () => { spec.method = inp.value.trim(); });
      body.appendChild(fieldLine('method id', inp, 'the catalogue (tools/level_editor/methods.json) was not served: type the method id the runner knows'));
    } else {
      const grid = el('div', { class: 'methods' });
      for (const x of list) grid.appendChild(methodCard(x, x.id === (method && method.id), () => { spec.method = x.id; draw(); }, record, dlg));
      // the ComfyUI workflows behind these methods, as files the ComfyUI page loads (tools/comfy_workflows, from `python tools/comfy.py --export`);
      // a finished job also keeps every graph it ran under its own card
      const wf = el('div', { class: 'jflows' }, el('b', { text: 'The ComfyUI workflows behind the methods' }),
        el('span', { class: 'muted small', text: ' (save a file, drag it into ' }), el('a', { href: COMFY_URL, target: '_blank', rel: 'noopener', text: 'the ComfyUI page' }),
        el('span', { class: 'muted small', text: '; every finished job keeps the exact graphs it ran on its card)' }));
      fetchJson('/api/workflows', null).then((r) => { for (const f of (r && r.files) || []) wf.appendChild(el('a', { class: 'jflow', href: '/workflows/' + encodeURIComponent(f), target: '_blank', rel: 'noopener', text: f.replace(/\.json$/, '') })); });
      body.appendChild(wf);
      body.appendChild(grid);
    }

    // 2. the recipe fields of the method (a dotted key is a path into a nested object: pose_drivers.back, badge.head_width)
    const fields = method && Array.isArray(method.recipe_fields) ? method.recipe_fields : [];
    if (fields.length || mode === 'look') {
      body.appendChild(el('h2', {}, 'What to paint', el('small', { text: 'the recipe the tool reads (written into variants[CODE].recipe for a look job)' })));
      if (!fields.length) body.appendChild(el('p', { class: 'help', text: 'no typed fields for this method in methods.json: the raw recipe below is what the tool gets' }));
      for (const f of fields) {
        if (f.key === 'death' && Array.isArray(m.deaths) && m.deaths.length) { body.appendChild(deathControl(f, m, spec, drivers, draw)); continue; }
        body.appendChild(fieldLine(f.label || f.key, recipeControl(f, U.getPath(spec.recipe, f.key), (v) => U.setPath(spec.recipe, f.key, v), { drivers, refs }), f.help));
      }
      const raw = el('details', { class: 'jfold' }, el('summary', { text: 'advanced: the raw recipe (JSON)' }));
      const ta = el('textarea', { class: 'mono', spellcheck: false });
      ta.value = JSON.stringify(spec.recipe, null, 2);
      ta.addEventListener('change', () => { try { spec.recipe = JSON.parse(ta.value || '{}'); ta.style.borderColor = ''; draw(); } catch (_) { ta.style.borderColor = 'var(--s8)'; } });
      raw.appendChild(ta);
      body.appendChild(raw);
    }

    // 2b. the job's own settings: jobs.py's SPECS for this kind when the server serves them (type, default, required,
    // help, options per field), else methods.json's job_fields; they land in spec.job, and the ones the runner reads as
    // flags / counts are mirrored there too. The keys with controls of their own (method, recipe, refs, drivers, the flags,
    // seed, seeds, note) are left out.
    const recipeKeys = new Set(fields.map((f) => f.key));
    const specFields = specs && specs[jk] && specs[jk].fields && typeof specs[jk].fields === 'object'
      ? Object.entries(specs[jk].fields).filter(([k]) => !OWN_KEYS.includes(k) && !recipeKeys.has(k)).map(([k, f]) => Object.assign({ key: k }, f || {}, { type: specType(f && f.type) }))
      : null;
    const mfields = method && Array.isArray(method.job_fields) ? method.job_fields : [];
    const jfields = specFields && specFields.length ? specFields.map((f) => Object.assign({}, mfields.find((x) => x.key === f.key) || {}, f, { help: f.help || (mfields.find((x) => x.key === f.key) || {}).help || '' })) : mfields;
    const modelFields = jfields.filter((f) => f.group === 'model');
    const assetFields = jfields.filter((f) => f.group !== 'model' && f.key !== 'dev');   // `dev` is the old switch: the model select covers it
    if (modelFields.length) {
      // the painter and its quality, apart from what the asset is (Garry: separate the model settings from the asset settings)
      body.appendChild(el('h2', {}, 'Model settings', el('small', { text: 'which painter and how many passes: Flux.2 Klein is quick, Flux.2 dev slower and finer; 0 passes = the default of that painter' })));
      if (!spec.job) spec.job = {};
      for (const f of modelFields) {
        const cur = spec.job[f.key] != null ? spec.job[f.key] : (f.key === 'model' && spec.flags.dev ? 'dev' : undefined);
        body.appendChild(fieldLine(f.label || f.key, recipeControl(f, cur, (v) => { setKey(spec.job, f.key, v); if (f.key === 'model') spec.flags.dev = v === 'dev'; }, { drivers, refs }), f.help));
      }
    }
    if (assetFields.length) {
      body.appendChild(el('h2', {}, 'Asset settings', el('small', { text: specFields && specFields.length ? `what this run makes, apart from the recipe (the ${jk} job's fields as jobs.py validates them)` : 'what this run makes, apart from the recipe' })));
      if (!spec.job) spec.job = {};
      // the continuation fields a pick sets (gen_ctl's --use-side / --view-cands / --use-view, --stage, the pick) live in a fold
      const CONT = ['stage', 'use_side', 'view_cands', 'use_view', 'pick', 'file', 'key'];
      const fold = el('details', { class: 'jfold' }, el('summary', { text: 'continuation fields (the picks set them; leave them for a new job)' }));
      let folded = 0;
      for (const f of assetFields) {
        const cur = spec.job[f.key] != null ? spec.job[f.key] : (f.key === 'seeds' ? spec.counts.seeds : (f.key in spec.flags ? spec.flags[f.key] : undefined));
        const line = fieldLine(f.label || f.key, recipeControl(f, cur, (v) => {
          setKey(spec.job, f.key, v);
          if (f.key === 'seeds') spec.counts.seeds = v == null ? undefined : Number(v);
          if (['dev', 'skip_qa', 'no_video', 'no_style_ref'].includes(f.key)) spec.flags[f.key] = !!v;
          if (f.key === 'seed') spec.flags.seed = Number(v) || 0;
        }, { drivers, refs }), f.help + (f.required ? ' (required)' : ''));
        if (CONT.includes(f.key) && !(spec.job[f.key])) { fold.appendChild(line); folded++; } else body.appendChild(line);
      }
      if (folded) body.appendChild(fold);
    }

    // 3. 2D references
    const takes2d = !method || !method.refs || method.refs['2d'] !== false;
    body.appendChild(el('h2', {}, '2D references', el('small', { text: takes2d ? 'pictures the painting follows' : 'this method takes no picture' })));
    if (takes2d) {
      body.appendChild(el('p', { class: 'help', text: m.ref_note || 'References steer by which pictures are passed, in what order, and the words; there is no strength number. The role says what the picture is for, the follow level picks the proven wording (identity · copy exactly = "Copy this exact object…"; identity · closely = "redraw this exact creature…"; style = "the same art style, do not copy its subjects"; pose and anatomy = the clay\'s anatomy, pose and camera). A picture reaches the front still (creatures) or the side (gen_ctl); the other views are edits of that painting.' }));
      const rows = el('div', { class: 'refrows' });
      spec.refs.forEach((ref, i) => rows.appendChild(refRow(ref, i, spec, refs, draw)));
      body.appendChild(rows);
      body.appendChild(el('div', { class: 'row' },
        el('button', { type: 'button', class: 'btn small', text: '+ Add a reference', onclick: () => { spec.refs.push({ path: '', role: 'identity', follow: 'closely', use: ['look'] }); draw(); } }),
        el('span', { class: 'cap-note', text: `(Klein has taken up to 4 references in practice: the style anchor counts as one, so up to ${3 - Math.max(0, spec.refs.length - 0) >= 0 ? 3 : 0} pictures; this is a practice rule, not a code limit)` }),
        el('label', { class: 'cb', title: 'drop the style anchor: the picture is the only reference (gen_edit_stills --no-style-ref)' }, (() => { const cb = el('input', { type: 'checkbox' }); cb.checked = !!spec.flags.no_style_ref; cb.addEventListener('change', () => { spec.flags.no_style_ref = cb.checked; }); return cb; })(), el('span', { text: 'no style anchor' }))));
    }

    // 4. 3D references
    const uses3d = method && method.refs && Array.isArray(method.refs['3d']) ? method.refs['3d'] : (mode === 'look' || mode === 'driver' ? ['animation', 'look', 'icon'] : ['icon', 'look']);
    body.appendChild(el('h2', {}, '3D references', el('small', { text: uses3d.length ? `for the ${uses3d.join(', ')}` : 'this method takes no 3D reference' })));
    if (uses3d.length) {
      body.appendChild(el('div', { class: 'insert3d', text: m.insert_3d_text || 'Preferred: Mixamo-style FBX Binary, 30 fps, "In Place" ticked, keyframe reduction none, with skin; or a GLB with a known rig (Mixamo bone names, or rig=sm). A model without an animation can still be the icon and look reference; a non-humanoid rigged model needs a depth driver (blender_depth_drivers.py).' }));
      const rows3 = el('div', { class: 'refrows' });
      if (!spec.refs3d) spec.refs3d = [];
      spec.refs3d.forEach((r3, i) => rows3.appendChild(ref3dRow(r3, i, spec, drivers, refs, uses3d, draw, dlg)));
      body.appendChild(rows3);
      body.appendChild(el('div', { class: 'row' },
        el('button', { type: 'button', class: 'btn small', text: '+ From the driver library', onclick: () => { spec.refs3d.push({ source: 'library', driver: '', uses: ['animation'] }); draw(); } }),
        el('button', { type: 'button', class: 'btn small', text: '+ Upload a model (FBX / GLB)', onclick: () => { spec.refs3d.push({ source: 'upload', slug: '', uses: uses3d.slice() }); draw(); } }),
        el('span', { class: 'cap-note', text: `${drivers.length} drivers in tools/dl/drivers/ · ${((refs && refs['3d']) || []).length} uploaded models` })));
    }

    // 5. what to make: looks, counts
    if (mode === 'look') {
      body.appendChild(el('h2', {}, 'Looks', el('small', { text: fixedCode ? `this job paints ${fixedCode}` : 'how many looks, and what each one changes' })));
      if (!fixedCode) {
        const n = el('input', { type: 'number', class: 'num', min: 1, max: 12, step: 1, value: spec.counts.looks || 1 });
        n.addEventListener('change', async () => { spec.counts.looks = Math.max(1, Math.min(12, Number(n.value) || 1)); state.codes = []; draw(); });
        body.appendChild(fieldLine('looks', n, 'one job per look; each lands in the JSON as a selectable look marked NEW (Remove for the rejects)'));
      }
      const rows = el('div', { class: 'lookrows' });
      body.appendChild(rows);
      const nLooks = fixedCode ? 1 : (spec.counts.looks || 1);
      const fill = (codes) => {
        clear(rows);
        for (let i = 0; i < nLooks; i++) {
          if (!state.overrides[i]) state.overrides[i] = {};
          rows.appendChild(lookRow(i, codes[i] || '?', state.overrides[i], method, spec, drivers, refs, fixedCode));
        }
      };
      if (fixedCode) fill([fixedCode]);
      else if (state.codes.length >= nLooks) fill(state.codes);
      else {
        fill([]);
        fetchJson(`/api/content/${encodeURIComponent(kind)}/${encodeURIComponent(id)}/next_codes?n=${nLooks}`, null).then((r) => {
          state.codes = r && r.ok && Array.isArray(r.codes) ? r.codes : nextCodes(record, nLooks, existingCodes);
          if (dlg.isConnected) fill(state.codes);
        });
      }
      const ic = el('input', { type: 'number', class: 'num', min: 0, max: 12, step: 1, value: spec.counts.icon_candidates || 0 });
      ic.addEventListener('change', () => { spec.counts.icon_candidates = Number(ic.value) || 0; });
      body.appendChild(fieldLine('icon candidates', ic, '0 = the icon is a crop of the front still (the pipeline\'s default); N = N icon candidates to pick from, as a job of their own after the look'));
      if (kind === 'hero') {
        const cc = el('input', { type: 'number', class: 'num', min: 0, max: 8, step: 1, value: spec.counts.cutout_candidates || 0 });
        cc.addEventListener('change', () => { spec.counts.cutout_candidates = Number(cc.value) || 0; });
        body.appendChild(fieldLine('cut-out candidates', cc, 'the title screen\'s cut-out candidates (660 × 888), a job of its own; 0 = none'));
      }
    } else {
      body.appendChild(el('h2', {}, 'Counts'));
      const seeds = el('input', { type: 'number', class: 'num', min: 1, max: 12, step: 1, value: spec.counts.seeds || 4 });
      seeds.addEventListener('change', () => { spec.counts.seeds = Number(seeds.value) || 4; });
      body.appendChild(fieldLine(mode === 'driver' ? 'frames / seeds' : 'candidates', seeds, mode === 'icon' ? 'how many icons to paint and pick from (20 s each; the Flux.2 dev model 4-5 min each)' : mode === 'driver' ? 'for a driver: unused (frames are a recipe field)' : 'how many candidates to pick from'));
    }

    // 6. seeds and re-roll
    body.appendChild(el('h2', {}, 'Seeds and re-rolls'));
    const seed = el('input', { type: 'number', class: 'num', step: 1, value: spec.flags.seed || 0 });
    seed.addEventListener('change', () => { spec.flags.seed = Number(seed.value) || 0; });
    body.appendChild(fieldLine('seed offset', seed, '0 = the tool\'s own seed for this id (seed_for(id)); N shifts every seed by N × 7919, so the same N gives the same pictures again'));
    const rr = el('div', { class: 'row' });
    for (const r of [{ v: '', label: 'none (first roll; cached work reused)', help: 'stills and clips already in tools/dl/ai_raw_anime and ai_anim are reused' }].concat(REROLL)) {
      const rb = el('input', { type: 'radio', name: 'reroll' }); rb.checked = (spec.reroll.mode || '') === r.v;
      rb.addEventListener('change', () => { spec.reroll.mode = r.v; draw(); });
      rr.appendChild(el('label', { class: 'cb', title: r.help }, rb, el('span', { text: r.label })));
    }
    body.appendChild(fieldLine('re-roll', rr, 'what the job throws away before it paints'));
    if (spec.reroll.mode === 'view') {
      const vs = el('select');
      for (const v of ['front', 'fd', 'side', 'bd', 'back']) vs.appendChild(el('option', { value: v, text: v, selected: spec.reroll.view === v }));
      vs.addEventListener('change', () => { spec.reroll.view = vs.value; });
      body.appendChild(fieldLine('the view', vs, 'gen_ctl --view-cands=<view>: candidates of that one view to pick from'));
    }

    // 7. flags
    body.appendChild(el('h2', {}, 'Flags'));
    const flags = el('div', { class: 'row' });
    for (const [k, label, help] of [['skip_qa', 'skip the vision QA', 'no LM Studio check of the stills: the first roll is kept (faster; check by eye)'], ['dev', 'Flux.2 dev model', 'the slower, finer model for the stills (205-286 s a still; the server restarts to load it)']]) {
      const cb = el('input', { type: 'checkbox' }); cb.checked = !!spec.flags[k];
      cb.addEventListener('change', () => { spec.flags[k] = cb.checked; });
      flags.appendChild(el('label', { class: 'cb', title: help }, cb, el('span', { text: label })));
    }
    body.appendChild(fieldLine('options', flags));
    const note = el('input', { type: 'text', class: 'txt', value: spec.note || '', placeholder: 'why this job (shown on its card)' });
    note.addEventListener('change', () => { spec.note = note.value.trim(); });
    body.appendChild(fieldLine('note', note));

    // 8. the words
    const det = el('details', { class: 'jfold' }, el('summary', { text: 'Show the words that will be sent' }));
    const words = el('pre', { class: 'words' });
    det.addEventListener('toggle', () => { if (det.open) words.textContent = composeWords(m, method, Object.assign({}, spec, { recipe: Object.assign({}, spec.recipe, state.overrides[0] || {}) }), { kind, id, code: fixedCode || (state.codes[0] || ''), art_prompt: c.contentJson && c.contentJson.art_prompt }); });
    det.appendChild(words);
    body.appendChild(det);
  }

  /** The example of a method: its picture (tools/level_editor/examples/) and, when the strip it names is reachable, a
   *  hover player of that look (the base look when the code is empty). Players go into `holder` for destroy(). */
  function methodExample(x, holder) {
    const ex = el('div', { class: 'mex' });
    if (x.example && x.example.image) ex.appendChild(exampleImg(x.example.image));
    if (x.example && x.example.strip && x.example.strip.id && typeof LookGrid !== 'undefined') {
      const st = x.example.strip;
      recordFor(st.kind, st.id).then((rec) => {
        if (!rec || !ex.isConnected) return;
        const looks = rec.looks || rec.variants || [];
        const look = (st.code ? looks.find((l) => l.code === st.code) : null) || looks.find((l) => l.base) || looks.find((l) => l.code === (rec.play || rec.variant)) || looks[0];
        if (!look || !(look.anims || rec.anims)) return;
        const p = StripPlayer.create(LookGrid.playerOpts(st.kind === 'hero' ? 'hero' : 'enemy', rec, look, { mode: 'hover', zoom: 0.5, anim: 'run', label: `${st.id} ${look.code}` }));
        if (holder) holder.push(p);
        ex.appendChild(el('span', { class: 'mex-strip' }, p.el, el('span', { class: 'muted small', text: `${st.id} ${look.code}: hover to play` })));
      });
    }
    if (!ex.childNodes.length) ex.appendChild(el('span', { class: 'muted small', text: 'no example picture' }));
    return ex;
  }

  function methodCard(x, on, pick, record, dlg) {
    const card = el('div', { class: 'mcard' + (on ? ' on' : ''), onclick: pick });
    const rb = el('input', { type: 'radio', name: 'method' }); rb.checked = on;
    card.appendChild(el('h3', {}, rb, el('span', { text: x.name || x.id }), x.time ? el('span', { class: 'mtime', text: `~${fmtMin(x.time.median_s)}`, title: `median ${fmtMin(x.time.median_s)}, worst seen ${fmtMin(x.time.worst_s)}` }) : null));
    if (x.summary) card.appendChild(el('p', { style: 'margin:0', text: x.summary }));
    card.appendChild(methodExample(x, dlg.__players));
    const row = (label, v, cls) => { if (v == null || (Array.isArray(v) && !v.length)) return; card.appendChild(el('div', { class: 'mrow ' + (cls || '') }, el('b', { text: label }), el('span', { text: Array.isArray(v) ? v.join(' · ') : String(v) }))); };
    row('needs', x.needs);
    row('produces', x.produces);
    if (x.counts && typeof x.counts === 'object') row('makes', Object.entries(x.counts).map(([k, v]) => `${v} ${k}`).join(', '));
    if (x.time) row('time', `median ${fmtMin(x.time.median_s)} · worst ${fmtMin(x.time.worst_s)}${x.per_seed_s ? ' · ' + fmtMin(x.per_seed_s) + ' a candidate' : ''}`);
    const r = x.runner || {};
    if (Array.isArray(r.stages) && r.stages.length) row('stops', r.stages.map((s) => `${s.name}${s.then === 'waiting' ? ' → you pick' : ''}`).join(' → '));
    else if (r.then === 'waiting') row('stops', 'paints, then you pick one');
    if (Array.isArray(r.pre_steps) && r.pre_steps.length) row('pre-steps', r.pre_steps.map((s) => s.tool).join(' → '));
    if (Array.isArray(x.weaknesses) && x.weaknesses.length) card.appendChild(el('div', { class: 'mrow mweak' }, el('b', { text: 'watch for' }), el('ul', {}, x.weaknesses.map((w) => el('li', { text: w })))));
    if (x.refs) row('references', [x.refs['2d'] ? 'a picture' : 'no picture'].concat(Array.isArray(x.refs['3d']) && x.refs['3d'].length ? ['3D for the ' + x.refs['3d'].join(', ')] : []));
    return card;
  }

  /** The `death` recipe field from methods.json's `deaths` table (value, name, text, seconds); a driven fall asks for its
   *  driver and writes `pose:<driver>`. */
  function deathControl(f, m, spec, drivers, draw) {
    const cur = U.getPath(spec.recipe, 'death');
    const curVal = cur == null ? (f.default != null ? String(f.default) : '') : String(cur);
    const isPose = curVal.startsWith('pose:');
    const sel = el('select');
    for (const d of m.deaths) sel.appendChild(el('option', { value: d.value, text: `${d.name}${d.seconds ? ' · ~' + d.seconds + ' s' : ''}`, selected: d.value === 'pose:<driver>' ? isPose : d.value === curVal }));
    sel.addEventListener('change', () => { U.setPath(spec.recipe, 'death', sel.value === 'pose:<driver>' ? 'pose:death_back' : sel.value); draw(); });
    const chosen = m.deaths.find((d) => (d.value === 'pose:<driver>' ? isPose : d.value === curVal));
    const wrap = el('div', { class: 'row' }, sel);
    if (isPose) {
      const ds = el('select', { title: 'the one-shot driver of the fall' });
      for (const d of drivers) ds.appendChild(el('option', { value: d.name, text: d.name, selected: 'pose:' + d.name === curVal }));
      if (!drivers.some((d) => 'pose:' + d.name === curVal)) ds.appendChild(el('option', { value: curVal.slice(5), text: curVal.slice(5), selected: true }));
      ds.addEventListener('change', () => U.setPath(spec.recipe, 'death', 'pose:' + ds.value));
      wrap.appendChild(ds);
    }
    return fieldLine(f.label || 'death', wrap, (chosen ? chosen.text + ' ' : '') + (f.help || ''));
  }
  function exampleImg(path) {
    const url = /^(https?:)?\//.test(path) ? path : '/' + String(path).replace(/^\.?\//, '');
    const img = el('img', { src: url, alt: '', loading: 'lazy', title: 'click to zoom' });
    img.addEventListener('click', (e) => { e.stopPropagation(); StripPlayer.openImage(url, path); });
    img.addEventListener('error', () => { img.replaceWith(el('span', { class: 'muted small', text: `(example picture missing: ${path})` })); });
    return img;
  }

  function refRow(ref, i, spec, refs, draw) {
    const row = el('div', { class: 'refrow' });
    const role = el('select', { title: 'what the picture is for' });
    for (const r of ROLES) role.appendChild(el('option', { value: r.v, text: r.label, selected: r.v === ref.role }));
    role.addEventListener('change', () => { ref.role = role.value; });
    const follow = el('select', { title: 'how closely: picks the proven wording' });
    for (const f of FOLLOW) follow.appendChild(el('option', { value: f.v, text: f.label, selected: f.v === ref.follow }));
    follow.addEventListener('change', () => { ref.follow = follow.value; });
    const file = el('select', { title: 'a picture under tools/dl/uploads/2d/' });
    file.appendChild(el('option', { value: '', text: '(pick a picture)' }));
    for (const r of (refs && refs['2d']) || []) file.appendChild(el('option', { value: r.path || r.url || r.name, text: r.name, selected: (r.path || r.url || r.name) === ref.path }));
    if (ref.path && ![...file.options].some((o) => o.value === ref.path)) file.appendChild(el('option', { value: ref.path, text: ref.path, selected: true }));
    file.addEventListener('change', () => { ref.path = file.value; });
    const up = el('input', { type: 'file', accept: '.png,.jpg,.jpeg,.webp', style: 'display:none' });
    up.addEventListener('change', async () => {
      const f = up.files && up.files[0];
      if (!f) return;
      App.status(`uploading ${f.name}…`, 'busy');
      const res = await upload(f, '2d');
      if (!res.ok) { App.status(`upload failed: ${res.error}`, 'bad'); return; }
      ref.path = res.path || res.url;
      App.status(`uploaded ${f.name}`, 'good');
      await fetchRefs(); draw();
    });
    const note = el('input', { type: 'text', value: ref.note || '', placeholder: 'note (what to take from it)' });
    note.addEventListener('change', () => { ref.note = note.value.trim(); });
    row.append(role, follow, el('span', { class: 'row' }, file, el('button', { type: 'button', class: 'btn small', text: 'Upload…', onclick: () => up.click() }), up), note,
      el('button', { type: 'button', class: 'btn small ghost', text: '✕', title: 'drop this reference', onclick: () => { spec.refs.splice(i, 1); draw(); } }));
    return row;
  }

  function ref3dRow(r3, i, spec, drivers, refs, uses3d, draw, dlg) {
    const row = el('div', { class: 'refrow r3d' });
    const src = el('select');
    for (const [v, label] of [['library', 'driver library'], ['upload', 'uploaded model']]) src.appendChild(el('option', { value: v, text: label, selected: r3.source === v }));
    src.addEventListener('change', () => { r3.source = src.value; draw(); });
    const mid = el('div', { class: 'drvpick' });
    if (r3.source === 'upload') {
      const sel = el('select');
      sel.appendChild(el('option', { value: '', text: '(pick an uploaded model)' }));
      for (const u of (refs && refs['3d']) || []) sel.appendChild(el('option', { value: u.slug, text: `${u.slug} (${u.file || ''}${u.size ? ', ' + Math.round(u.size / 1048576) + ' MB' : ''})`, selected: u.slug === r3.slug }));
      sel.addEventListener('change', () => { r3.slug = sel.value; draw(); });
      const up = el('input', { type: 'file', accept: '.fbx,.glb,.gltf,.obj,.dae,.blend', style: 'display:none' });
      up.addEventListener('change', async () => {
        const f = up.files && up.files[0];
        if (!f) return;
        App.status(`uploading ${f.name} (${Math.round(f.size / 1048576)} MB)…`, 'busy');
        const res = await upload(f, '3d');
        if (!res.ok) { App.status(`upload failed: ${res.error}`, 'bad'); return; }
        r3.slug = res.slug || f.name;
        App.status(`uploaded ${f.name}: the probe job is queued (what this model can do shows here when it ends)`, 'good');
        await fetchRefs(); draw();
      });
      mid.append(sel, el('button', { type: 'button', class: 'btn small', text: 'Upload…', onclick: () => up.click() }), up);
      const u = ((refs && refs['3d']) || []).find((x) => x.slug === r3.slug);
      if (u) mid.appendChild(probeBox(u));
    } else {
      const d = drivers.find((x) => x.name === r3.driver);
      const btn = el('button', { type: 'button', class: 'btn small', text: d ? `${d.name} (${d.kind || '?'})` : 'pick a driver…', onclick: () => driverPicker(drivers, r3.driver, (name) => { r3.driver = name; draw(); }, dlg) });
      mid.appendChild(btn);
      if (d && d.sheet) { const im = el('img', { src: d.sheet, alt: '', title: 'the driver\'s sheet: click to zoom' }); im.addEventListener('click', () => StripPlayer.openImage(d.sheet, d.name)); mid.appendChild(im); }
      if (d) mid.appendChild(el('span', { class: 'muted small', text: `${d.kind === 'depth' ? 'depth videos' : 'OpenPose frames'} · ${(d.views || []).join(', ')}${d.frames ? ' · ' + d.frames + ' frames' : ''}` }));
    }
    const uses = el('div', { class: 'uses' });
    if (!Array.isArray(r3.uses)) r3.uses = [];
    for (const u of USES) {
      if (!uses3d.includes(u.v)) continue;
      const cb = el('input', { type: 'checkbox' }); cb.checked = r3.uses.includes(u.v);
      cb.addEventListener('change', () => { if (cb.checked) { if (!r3.uses.includes(u.v)) r3.uses.push(u.v); } else r3.uses = r3.uses.filter((x) => x !== u.v); });
      uses.appendChild(el('label', { title: u.v === 'animation' ? 'how it moves: OpenPose or depth frames drive the clips' : u.v === 'look' ? 'the clay or look render is the painting reference (recipe.look_ref)' : 'a 3/4 render (yaw 35°, pitch 20°) is the icon\'s reference' }, cb, el('span', { text: u.label })));
    }
    row.append(src, mid, uses, el('button', { type: 'button', class: 'btn small ghost', text: '✕', onclick: () => { spec.refs3d.splice(i, 1); draw(); } }));
    return row;
  }

  /** What the probe (blender_ref.py mode=probe → probe.json) says this model can do: the synthesis §5.3 decision tree. */
  function probeBox(u) {
    const p = u.probe;
    if (!p) return el('div', { class: 'probe', text: 'probing… (a ref_probe job reads the file in Blender: armatures, actions, meshes, size; this line fills in when it ends)' });
    const arm = Array.isArray(p.armatures) && p.armatures.length;
    const acts = Array.isArray(p.actions) ? p.actions : [];
    const meshes = p.meshes != null ? p.meshes : (Array.isArray(p.meshes) ? p.meshes.length : 0);
    let text, bad = false;
    if (!arm && !meshes) { text = 'not a model Blender can read (no armature, no mesh)'; bad = true; }
    else if (!arm || !acts.length) text = 'This model has no animation clip, so it cannot drive a walk; it can be the icon\'s reference and the look reference. For a walk export it from Mixamo as FBX Binary, 30 fps, In Place, keyframe reduction none, or a GLB that carries its animation.';
    else if (p.rig_guess === 'mixamo') text = `Mixamo-style humanoid with ${acts.length} clip${acts.length > 1 ? 's' : ''} (${acts.map((a) => a.name + (a.seconds ? ' ' + a.seconds.toFixed(1) + ' s' : '')).join(', ')}): OpenPose drivers (24 frames for a run, 12 for a walk; loop or one-shot) and depth drivers.`;
    else if (p.rig_guess === 'sm') text = `A Synty-style (Bone_SM_*) humanoid with ${acts.length} clip${acts.length > 1 ? 's' : ''}: OpenPose drivers with rig=sm, and depth drivers.`;
    else text = `A rigged model (${p.rig_guess || 'other'} rig) with ${acts.length} clip${acts.length > 1 ? 's' : ''}: depth drivers of its own motion (pick the walk / death / idle clip); for OpenPose drivers a bone map is needed (ask Claude).`;
    return el('div', { class: 'probe' + (bad ? ' bad' : ''), text: `probe: ${text}${p.dimensions ? ' · size ' + (Array.isArray(p.dimensions) ? p.dimensions.map((x) => Number(x).toFixed(2)).join(' × ') : p.dimensions) : ''}${p.forward_guess ? ' · forward ' + p.forward_guess : ''}` });
  }

  /** The frame-file pattern of a driver's view: /api/drivers gives frames_url "/dl/drivers/<name>/<view>/" (a literal
   *  <view> placeholder) and frame_pattern "driver_%02d.png" | "ctl_%02d.png". */
  function driverFrames(d, view) {
    let base = String(d.frames_url || `/dl/drivers/${d.name}/<view>/`);
    base = base.includes('<view>') ? base.replace('<view>', view) : base.replace(/\/?$/, '/') + view + '/';
    return base + (d.frame_pattern || (d.kind === 'depth' ? 'ctl_%02d.png' : 'driver_%02d.png'));
  }

  function driverPicker(drivers, current, pick, parent) {
    const dlg = document.createElement('dialog');
    dlg.className = 'sp-modal';
    const grid = el('div', { class: 'drvgrid' });
    const players = [];
    for (const d of drivers) {
      const card = el('div', { class: 'drvcard' + (d.name === current ? ' on' : ''), onclick: () => { pick(d.name); dlg.close(); } });
      card.appendChild(el('b', { text: d.name }));
      card.appendChild(el('span', { text: `${d.kind === 'depth' ? 'depth videos' : 'OpenPose'} · ${(d.views || []).join(', ') || '?'}${d.frames ? ' · ' + d.frames + ' frames' : ''}${d.meta && d.meta.fbx ? ' · ' + d.meta.fbx : ''}${d.meta && d.meta.action ? ' · ' + d.meta.action : ''}` }));
      if (d.sheet) card.appendChild(el('img', { src: d.sheet, alt: '', loading: 'lazy' }));
      const view = (d.views || []).includes('side') ? 'side' : (d.views || [])[0];
      if (d.frames_url && view && d.frames) {
        const p = StripPlayer.createSeq({ pattern: driverFrames(d, view), count: Number(d.frames) || 12, fps: 12, size: 96, mode: 'hover', label: `${d.name} ${view}` });
        players.push(p);
        card.appendChild(p.el);
      }
      grid.appendChild(card);
    }
    const filter = el('input', { type: 'search', class: 'txt', placeholder: 'filter…' });
    filter.addEventListener('input', () => { const f = filter.value.toLowerCase(); for (const c of grid.children) c.hidden = f && !c.textContent.toLowerCase().includes(f); });
    dlg.append(el('div', { class: 'sp-modal-head' }, el('b', { text: `the driver library · ${drivers.length}` }), el('span', { class: 'muted small', text: 'hover a card to play its frames; click to pick' }), filter, el('span', { class: 'spacer' }), el('button', { type: 'button', class: 'btn small', text: '✕', onclick: () => dlg.close() })), grid);
    document.body.appendChild(dlg);
    dlg.addEventListener('close', () => { for (const p of players) p.destroy(); dlg.remove(); });
    dlg.showModal();
  }

  function lookRow(i, code, ov, method, spec, drivers, refs, fixed) {
    const det = el('details', { class: 'lookrow', open: i === 0 && fixed });
    const sum = el('summary', {}, el('b', { text: `Look ${i + 1}` }), el('span', { class: 'muted', text: fixed ? '' : 'will become' }), el('code', { text: code }), el('span', { class: 'muted small', text: Object.keys(ov).length ? `${Object.keys(ov).length} override${Object.keys(ov).length > 1 ? 's' : ''}` : 'no overrides: the shared recipe' }));
    det.appendChild(sum);
    const keys = [
      { key: 'prompt', type: 'textarea', help: 'this look\'s subject words (else the shared recipe\'s / the JSON\'s art_prompt)' },
      { key: 'keep', type: 'text', help: 'what every view keeps (gen_ctl keep / edit stills keep)' },
      { key: 'detail', type: 'text', help: 'the finish words (gen_ctl detail)' },
      { key: 'motion', type: 'textarea', help: 'how it moves, for the clips' },
      { key: 'anim_negative', type: 'text', help: 'what the clips must not do' },
      { key: 'seed', type: 'int', help: 'a seed offset for this look only' },
      { key: 'screen', type: 'select', options: ['green', 'blue'], help: 'the keying screen (blue for a green creature)' },
      { key: 'directions', type: 'select', options: ['2', '8'], help: '2 = front and back; 8 = side and three-quarter views too' },
    ];
    for (const f of keys) det.appendChild(fieldLine(f.key, recipeControl(f, ov[f.key], (v) => { setKey(ov, f.key, v); }, { drivers, refs }), f.help));
    const drv = el('select');
    drv.appendChild(el('option', { value: '', text: '(the shared drivers)' }));
    for (const d of drivers) drv.appendChild(el('option', { value: d.name, text: `${d.name} (${d.kind || '?'})`, selected: d.name === ov.driver }));
    drv.addEventListener('change', () => setKey(ov, 'driver', drv.value));
    det.appendChild(fieldLine('driver', drv, 'this look walks on another driver'));
    return det;
  }

  async function upload(file, kind) {
    try {
      const r = await fetch('/api/upload', { method: 'POST', headers: { 'X-Kind': kind, 'X-Filename': file.name.replace(/[^A-Za-z0-9._-]/g, '_'), 'Content-Type': 'application/octet-stream' }, body: file });
      const res = await r.json();
      if (!r.ok && res.ok !== false) res.ok = false;
      if (!res.ok && !res.error) res.error = `HTTP ${r.status}`;
      return res;
    } catch (e) { return { ok: false, error: e.message }; }
  }

  async function submit(c) {
    const { kind, id, mode, job, m, all, state, fixedCode, dlg, err, queueBtn, record, existingCodes, specs } = c;
    const spec = state.spec;
    const method = all.find((x) => x.id === spec.method) || null;
    if (!spec.method) { err.textContent = 'pick a method'; return; }
    for (const ref of spec.refs || []) if (!ref.path) { err.textContent = 'a 2D reference row has no picture: pick one or drop the row'; return; }
    for (const r3 of spec.refs3d || []) if ((r3.source === 'library' && !r3.driver) || (r3.source === 'upload' && !r3.slug)) { err.textContent = 'a 3D reference row has no driver or model: pick one or drop the row'; return; }
    // the 3D rows become drivers + refs for the runner
    const drivers = {};
    const extraRefs = [];
    for (const r3 of spec.refs3d || []) {
      const d = r3.source === 'library' ? (S.drivers || []).find((x) => x.name === r3.driver) : null;
      if (r3.uses.includes('animation')) { if (r3.source === 'library' && d) drivers[d.kind === 'depth' ? 'depth' : 'pose'] = d.name; else if (r3.source === 'upload') drivers.upload = r3.slug; }
      if (r3.uses.includes('look')) extraRefs.push({ path: r3.source === 'library' ? `tools/dl/drivers/${r3.driver}/side/clay.png` : `tools/dl/uploads/3d/${r3.slug}/side/clay.png`, role: 'pose', follow: 'closely', use: ['look'] });
      if (r3.uses.includes('icon')) extraRefs.push({ path: r3.source === 'library' ? `tools/dl/drivers/${r3.driver}/side/look.png` : `tools/dl/uploads/3d/${r3.slug}/icon_ref.png`, role: 'identity', follow: 'copy', use: ['icon'] });
    }
    const base = Object.assign({}, spec, { drivers: Object.assign({}, spec.drivers, drivers), refs: (spec.refs || []).concat(extraRefs) });
    delete base.looks;
    const jk = jobKind(mode, method, kind);
    queueBtn.disabled = true;
    err.textContent = '';
    try {
      if (job) {
        const one = Object.assign({}, base, { recipe: Object.assign({}, base.recipe, state.overrides[0] || {}) });
        const res = await post(`/api/jobs/${encodeURIComponent(job.id)}`, { spec: flatten(one, job.kind, specs), title: job.title });
        if (!res.ok) { err.textContent = res.error; queueBtn.disabled = false; return; }
        toast(`job #${shortId(job.id)} changed`);
        dlg.close(); await poll(); return;
      }
      const n = mode === 'look' ? (fixedCode ? 1 : (spec.counts.looks || 1)) : 1;
      let codes = fixedCode ? [fixedCode] : state.codes;
      if (mode === 'look' && codes.length < n) {
        const r = await fetchJson(`/api/content/${encodeURIComponent(kind)}/${encodeURIComponent(id)}/next_codes?n=${n}`, null);
        codes = r && r.ok && Array.isArray(r.codes) ? r.codes : nextCodes(record, n, existingCodes);
      }
      const made = [];
      for (let i = 0; i < n; i++) {
        const ov = state.overrides[i] || {};
        const one = Object.assign({}, base, { recipe: Object.assign({}, base.recipe, ov) });
        if (ov.driver) one.drivers = Object.assign({}, one.drivers, { pose: ov.driver });
        delete one.recipe.driver;
        const target = { kind, id };
        if (mode === 'look') target.code = codes[i];
        else if (fixedCode) target.code = fixedCode;
        const title = `${record ? (record.name || id) : id}${target.code ? ' ' + target.code : ''} · ${method ? method.name : spec.method}`;
        const res = await post('/api/jobs', { kind: jk, target, spec: flatten(one, jk, specs), title });
        if (!res.ok) { err.textContent = `${target.code || id}: ${res.error}`; break; }
        made.push(res.job ? res.job.id : target.code || id);
        // the counts beside a look: icon candidates and, for a hero, title cut-out candidates are jobs of their own
        if (mode === 'look' && spec.counts.icon_candidates > 0) {
          const ic = flatten({ method: 'icon_cands', recipe: {}, refs: [], drivers: {}, flags: { dev: !!spec.flags.dev }, counts: { seeds: spec.counts.icon_candidates }, job: { subject: one.recipe.art_prompt || one.recipe.prompt || '', screen: one.recipe.screen || 'green', ref: '' }, note: `icon candidates for ${target.code}` }, 'icon_cands', specs);
          const r2 = await post('/api/jobs', { kind: 'icon_cands', target, spec: ic, title: `${target.id} ${target.code} · icon candidates ×${spec.counts.icon_candidates}` });
          if (r2.ok && r2.job) made.push(r2.job.id); else err.textContent = `icon candidates: ${r2.error}`;
        }
        if (mode === 'look' && kind === 'hero' && spec.counts.cutout_candidates > 0) {
          const tc = flatten({ method: 'hero_title', recipe: {}, refs: [], drivers: {}, flags: {}, counts: { seeds: spec.counts.cutout_candidates }, job: {}, note: '' }, 'hero_title', specs);
          const r3 = await post('/api/jobs', { kind: 'hero_title', target: { kind, id }, spec: tc, title: `${target.id} · title cut-out candidates ×${spec.counts.cutout_candidates}` });
          if (r3.ok && r3.job) made.push(r3.job.id); else err.textContent = `cut-out candidates: ${r3.error}`;
        }
      }
      if (made.length) toast(`queued ${made.length} job${made.length > 1 ? 's' : ''}: ${made.map(shortId).join(', ')}`, { label: 'Open Jobs', onClick: () => App.switchTab('jobs') });
      if (made.length === n) dlg.close();
      await poll();
      if (mode === 'look' && made.length && typeof LookGrid !== 'undefined') {
        // the stubs landed in the JSON: the open grid shows them
        const kindList = kind === 'hero' ? 'heroes' : 'enemies';
        if (typeof Assets !== 'undefined' && typeof Assets.refreshRecord === 'function') { try { await Assets.refreshRecord(kind, id); } catch (_) { /* shown on the next render */ } }
        else if (kind !== 'hero' && typeof App.refreshCreatures === 'function') { try { await App.refreshCreatures(); } catch (_) { /* shown on the next render */ } }
        void kindList;
      }
    } finally { queueBtn.disabled = false; }
  }

  // start polling when the script loads (index.html loads jobs.js after app.js; App.init runs on DOMContentLoaded)
  if (typeof document !== 'undefined') {
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
  }

  return { render, poll, start, openForm, jobsFor, toast, openAsset, nextCodes, composeWords, methods, S, STATES, STATE_LABEL, REROLL, ROLES, FOLLOW, USES };
})();
if (typeof module !== 'undefined') module.exports = Jobs;
