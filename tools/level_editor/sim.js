// The Sim tab (pass 77, lane SIMUI). Garry: "Add a game sim tab which simulates a run ... simulate like 10 players
// (editable) and the output is the average ... charts per second showing: Player DPS, Player HP, Death, Difficulty
// (composition of enemy HP and atk, which are likely to be alive at that point), Coins (total gains), Total Damage Dealt
// (different sources breakdown as well), Kills (different enemies breakdown), hero level, total exp gained ... the sim
// requires a manual button press". Round 2 (his notes on the first version): the tab right after Timeline; the hero and
// his Upgrade board talent by talent (presets none / a quarter / half / full / my save); an honest ETA and why it takes
// what it takes; crowd HP and attack replaced by Danger (health lost a second), Keeping up (seconds of his DPS to clear
// the crowd, the boss apart) and Close crowd; what the run dashboard knows that helps judge a timeline; one page that
// scrolls as a whole, so no chart is ever cut off.
//
// The sim plays the REAL game: N headless runs of the saved map driven by a bot (game/tools/sim_run.gd), K at a time on
// a snapshot of game/ (tools/sim_batch.py, a job of kind "sim" on its own lane), averaged per second of play. The page,
// top to bottom: the settings card (Run sim, the ETA and why; nothing runs until it is pressed; unsaved map edits offer
// "Save and run"; Hide settings folds it to one line), the progress and Cancel while a sim runs, the history (Show,
// Compare, Keep, Delete), the header of the sim shown and its tiles, then its charts in five sections, each chart saying
// what it shows and how it was averaged, the stage starts and boss fights marked, one hover cursor shared by every chart,
// Table and CSV. The maths without the page (plain data in and out, reusable by the run dashboard): sim_model.js. The
// routes: sim_io.py (/api/sim/...). Pass 78: the charts' drawing moved to sim_plot.js, shared with analytics/dashboard.html.
'use strict';

const Sim = (() => {
  const { el, svg, clear } = U;
  const M = SimModel;
  const FAST = 2000, SLOW = 15000;
  const S = {
    meta: null, metaErr: '', form: null, history: [], status: null,
    current: null, currentId: '', compare: null, compareId: '', follow: '',
    hover: null, raw: false, tables: new Set(), confirm: false, busy: '',
    drawn: [], panel: null, pollTimer: null, lastSeenDone: -1, lastActive: '', polling: false,
    collapsed: false, histOpen: true,
  };
  const LS_FORM = '88fits-sim-form';
  const LS_FOLD = '88fits-sim-fold';
  try { const f = JSON.parse(localStorage.getItem(LS_FOLD) || 'null'); if (f) { S.collapsed = !!f.settings; S.histOpen = f.history !== false; } } catch (_) { /* defaults */ }

  // ------------------------------------------------------------------ server

  async function getJSON(url) {
    const r = await fetch(url, { cache: 'no-store' });
    if (r.status === 404) {
      const t = await r.text();
      const e = new Error(/unknown API path/.test(t) ? 'old-server' : `HTTP 404: ${t.slice(0, 120)}`);
      e.status = 404;
      throw e;
    }
    if (!r.ok) throw new Error(`${url}: HTTP ${r.status}`);
    return r.json();
  }

  async function post(url, body) {
    try {
      const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) });
      const j = await r.json().catch(() => ({ ok: false, error: `HTTP ${r.status}` }));
      if (!r.ok && j.ok === undefined) j.ok = false;
      return j;
    } catch (e) {
      return { ok: false, error: e.message };
    }
  }

  async function loadMeta() {
    try {
      S.meta = await getJSON('/api/sim/settings');
      S.metaErr = '';
      if (!S.form) {
        let draft = null;
        try { draft = JSON.parse(localStorage.getItem(LS_FORM) || 'null'); } catch (_) { draft = null; }
        S.form = Object.assign({}, M.DEFAULTS, S.meta.defaults || {}, S.meta.saved || {}, draft || {});
      }
      normalizeForm();
    } catch (e) {
      S.metaErr = e.message === 'old-server'
        ? 'This Level Editor\'s server started before the Sim tab existed: close the Level Editor\'s window and start tools\\level_editor.cmd again.'
        : `The server did not answer: ${e.message}`;
    }
  }

  /** The form made whole against what the server offers: a board talent by talent (from its preset when a draft has
   *  none), a death policy the runner knows, at once 0 = auto. */
  function normalizeForm() {
    const f = S.form;
    const meta = S.meta || {};
    if (!f.talents || typeof f.talents !== 'object') {
      const pre = (meta.presets || []).find((p) => Math.abs(Number(p.board) - Number(f.board)) < 1e-6 && p.key !== 'save') || (meta.presets || [])[1];
      f.talents = pre ? Object.assign({}, pre.talents) : {};
      f.board_label = pre ? pre.label : '';
    }
    const deaths = (meta.deaths || []).map((d) => d.value);
    if (deaths.length && !deaths.includes(f.death)) f.death = deaths.includes('end') ? 'end' : deaths[0];
    if (!(Number(f.workers) >= 0)) f.workers = 0;
    // pass 80 (lane BOT): the bot's options, a preset and the keys set over it (an older draft: the default preset)
    if (!f.bot || typeof f.bot !== 'object' || Array.isArray(f.bot)) f.bot = {};
    if (!f.bot.preset) f.bot = Object.assign({ preset: (meta.bot || {}).default || 'explorer' }, f.bot);
  }

  async function loadHistory() {
    try {
      const h = await getJSON('/api/sim/history');
      S.history = h.sims || [];
    } catch (e) { S.history = S.history || []; }
  }

  async function loadStatus() {
    try { S.status = await getJSON('/api/sim/status'); } catch (e) { S.status = null; }
  }

  async function loadResult(id) {
    if (!id) return null;
    try { return await getJSON(`/api/sim/result/${encodeURIComponent(id)}`); } catch (e) { return null; }
  }

  // ------------------------------------------------------------------ state helpers

  const RUNNING = ['starting', 'waiting', 'syncing', 'importing', 'running', 'aggregating'];
  const activeId = () => (S.status && S.status.sim_id && (S.status.job || (S.status.progress && RUNNING.includes(S.status.progress.state))) ? S.status.sim_id : '');
  const activeJob = () => (S.status && S.status.job) || null;
  const isActive = () => !!activeId() || !!activeJob();
  const histEntry = (id) => S.history.find((h) => h.id === id) || null;
  const heroName = (id) => { const h = S.meta && (S.meta.heroes || []).find((x) => x.id === id); return h ? h.name : id; };
  const maxWorkers = () => (S.meta && S.meta.max_workers) || 6;
  const autoWorkers = (players) => Math.max(1, Math.min(Number(players) || 1, maxWorkers()));
  const workersOf = (f) => (Number(f.workers) > 0 ? Math.min(Number(f.workers), Number(f.players) || 1) : autoWorkers(f.players));

  function simLabel(h) {
    if (!h) return '';
    const st = h.settings || {};
    const when = h.started ? new Date(h.started) : null;
    const hm = when && !isNaN(when.getTime()) ? `${when.getMonth() + 1}/${when.getDate()} ${String(when.getHours()).padStart(2, '0')}:${String(when.getMinutes()).padStart(2, '0')}` : '';
    return `${hm} · ${h.hero_name || heroName(st.hero)} ×${st.players} to ${M.fmtT(st.limit)}`;
  }

  function saveDraft() {
    try { localStorage.setItem(LS_FORM, JSON.stringify(S.form)); } catch (_) { /* a private window: the server keeps the last run's */ }
  }

  function saveFold() {
    try { localStorage.setItem(LS_FOLD, JSON.stringify({ settings: S.collapsed, history: S.histOpen })); } catch (_) { /* fine */ }
  }

  // ------------------------------------------------------------------ polling

  function schedule() {
    clearTimeout(S.pollTimer);
    const visible = App.S.tab === 'sim' && !document.hidden;
    if (!visible && !isActive()) return;
    S.pollTimer = setTimeout(poll, isActive() ? FAST : SLOW);
  }

  async function poll() {
    // one poll at a time (a tab switch or the window's focus can call it while one is in flight)
    if (S.polling) return;
    S.polling = true;
    try { await pollOnce(); } finally { S.polling = false; schedule(); }
  }

  async function pollOnce() {
    const wasActive = activeId() || (activeJob() && activeJob().id) || '';
    const hadJob = !!activeJob();   // a job's end is toasted by the Jobs tab already
    await loadStatus();
    const nowActive = activeId() || (activeJob() && activeJob().id) || '';
    const prog = S.status && S.status.progress;
    if (wasActive && !nowActive) {
      // the sim finished (or stopped): its result, the history and the measured speed again
      await loadHistory();
      await loadMeta();
      const id = S.lastActive || wasActive;
      if (id && histEntry(id) && histEntry(id).has_result) await show(id, true);
      const h = histEntry(id);
      if (h && !hadJob) App.toast(`Sim ${h.state === 'done' ? 'finished' : h.state}: ${simLabel(h)}`, { ms: 8000 });
      S.lastSeenDone = -1;
      draw();
    } else if (nowActive) {
      S.lastActive = activeId() || S.lastActive;
      const rp = prog ? prog.result_players || 0 : 0;
      if (rp !== S.lastSeenDone) {
        S.lastSeenDone = rp;
        await loadHistory();
        // a partial result as the runs finish: shown when the running sim is the one on screen (or nothing is), or
        // the one Garry just started with Run sim (it takes over the charts at its first finished run)
        if (rp > 0 && (!S.currentId || S.currentId === activeId() || S.follow === activeId())) { await show(activeId(), true); S.follow = ''; }
        draw();
      } else drawProgress();
    } else if (App.S.tab === 'sim') {
      drawProgress();
    }
  }

  document.addEventListener('visibilitychange', () => { if (!document.hidden && App.S.tab === 'sim') poll(); });

  // ------------------------------------------------------------------ actions

  async function show(id, quiet) {
    if (!id) return;
    const r = await loadResult(id);
    if (!r) { if (!quiet) App.status(`The sim ${id} has no result yet`, 'bad'); return; }
    S.current = r; S.currentId = id;
    if (S.compareId === id) { S.compare = null; S.compareId = ''; }
    S.hover = null;
  }

  async function setCompare(id) {
    if (!id) { S.compare = null; S.compareId = ''; draw(); return; }
    const r = await loadResult(id);
    if (!r) { App.status(`The sim ${id} has no result to compare`, 'bad'); return; }
    S.compare = r; S.compareId = id;
    draw();
  }

  function formSettings() {
    const f = S.form;
    return { hero: f.hero, players: f.players, workers: Number(f.workers) > 0 ? f.workers : 0, limit: f.limit, board: f.board, talents: f.talents || {},
      board_label: f.board_label || '', death: f.death, seed: f.seed, map: App.S.mapId || f.map, fps: f.fps || 60, note: f.note || '',
      bot: f.bot || {} };
  }

  async function runSim(saveFirst) {
    if (saveFirst) {
      S.busy = 'saving the map…'; draw();
      await App.save();
      if (App.dirty()) { S.busy = ''; S.confirm = false; draw(); App.status('The map was not saved, so the sim did not start (see the status line)', 'bad'); return; }
    }
    const meta = S.meta || {};
    const { settings, problems } = M.cleanSettings(formSettings(), { max_players: meta.max_players, max_workers: meta.max_workers, limit_min: meta.limit_min,
      limit_max: meta.limit_max, cores: meta.cores, deaths: (meta.deaths || []).map((d) => d.value) });
    if (problems.length) { App.status('Sim settings: ' + problems.join('; '), 'bad'); return; }
    settings.workers = Number(S.form.workers) > 0 ? settings.workers : 0;   // auto stays auto (the server resolves it)
    S.busy = 'queueing the sim…'; S.confirm = false; draw();
    const res = await post('/api/sim/run', { settings });
    S.busy = '';
    if (!res.ok) { App.status(`The sim did not start: ${res.error || 'no reason given'}`, 'bad'); draw(); return; }
    saveDraft();
    S.lastActive = res.sim_id || '';
    S.follow = res.sim_id || '';
    App.status(`Sim queued: ${settings.players} runs of ${heroName(settings.hero)} to ${M.fmtT(settings.limit)}`, 'good');
    await loadStatus();
    await loadHistory();
    draw();
    schedule();
  }

  // pass 80 (lane WATCH): the Watch button: tools/watch.py with the tab's hero, board, seed and bot (POST /api/sim/watch)
  async function watchRun() {
    S.watching = true; draw();
    const res = await post('/api/sim/watch', { settings: formSettings() });
    S.watching = false; draw();
    if (!res.ok) { App.status(`The Watch did not start: ${res.error || 'no reason given'}`, 'bad'); return; }
    App.status(`Watch: ${heroName(S.form.hero)}, seed ${S.form.seed}: ${res.message || 'starting'}`, 'good');
  }

  async function cancelSim() {
    const id = activeId() || S.lastActive;
    const job = activeJob();
    let res;
    if (job && job.state === 'queued' && !id) res = await post(`/api/jobs/${encodeURIComponent(job.id)}/cancel`, {});
    else res = await post(`/api/sim/${encodeURIComponent(id || (job && job.plan && job.plan.sim_id) || '')}/cancel`, {});
    App.status(res.ok ? 'Sim cancelled: the runs already finished stay as a partial result' : `Cancel: ${res.error}`, res.ok ? 'good' : 'bad');
    setTimeout(poll, 800);
  }

  async function keepSim(id, flag) {
    const res = await post(`/api/sim/${encodeURIComponent(id)}/keep`, { keep: flag });
    if (!res.ok) App.status(`Keep: ${res.error}`, 'bad');
    await loadHistory(); draw();
  }

  async function deleteSim(id) {
    if (!confirm('Delete this sim and its runs\' files? (It cannot be undone.)')) return;
    const res = await post(`/api/sim/${encodeURIComponent(id)}/delete`, {});
    if (!res.ok) { App.status(`Delete: ${res.error}`, 'bad'); return; }
    if (S.currentId === id) { S.current = null; S.currentId = ''; }
    if (S.compareId === id) { S.compare = null; S.compareId = ''; }
    await loadHistory(); draw();
  }

  async function releaseLock(force) {
    const res = await post('/api/sim/unlock', { force });
    App.status(res.ok ? 'The sim lock is free' : `The sim lock: ${res.error}`, res.ok ? 'good' : 'bad');
    await loadStatus(); draw();
  }

  // ------------------------------------------------------------------ render

  async function render(panel) {
    S.panel = panel;
    if (!S.meta && !S.metaErr) {
      clear(panel).appendChild(el('p', { class: 'muted', text: 'Loading the Sim tab…' }));
      await loadMeta();
      await Promise.all([loadHistory(), loadStatus()]);
      if (!S.current) {
        const first = S.history.find((h) => h.has_result && h.state !== 'running') || S.history.find((h) => h.has_result);
        if (first) await show(first.id, true);
      }
    } else refreshMeta();   // the measured speed, the saved map's code and the lock may have changed since
    draw();
    schedule();
  }

  /** The settings route again (cheap): the page redraws only when the ETA's speed, the saved maps or the lock moved. */
  async function refreshMeta() {
    if (!S.meta) return;
    const sig = () => JSON.stringify([S.meta && S.meta.map_revs, S.meta && S.meta.speed, S.meta && S.meta.lock, S.meta && S.meta.snapshot, S.meta && S.meta.caps]);
    const before = sig();
    await loadMeta();
    if (sig() !== before && App.S.tab === 'sim') draw();
  }

  /** The whole tab, top to bottom, in ONE scroll (round 2: no inner scroll areas, so nothing is ever cut off). */
  function draw() {
    const panel = S.panel;
    if (!panel || App.S.tab !== 'sim') return;
    const keepScroll = panel.scrollTop;
    clear(panel);
    if (S.metaErr) {
      panel.appendChild(el('div', { class: 'sim-empty card' }, el('h2', { text: 'Run sim' }), el('p', { class: 'warn-text', text: S.metaErr })));
      return;
    }
    const wrap = el('div', { class: 'sim' });
    wrap.appendChild(runCard());
    const pc = progressCard();
    if (pc) wrap.appendChild(pc);
    wrap.appendChild(historyCard());
    panel.appendChild(wrap);
    if (S.current) {
      wrap.appendChild(headCard());
      wrap.appendChild(tilesRow());
      const charts = el('div', { class: 'sim-sections' });
      wrap.appendChild(charts);
      wrap.appendChild(runsTable());
      drawCharts(charts);
    } else {
      wrap.appendChild(emptyCard());
      S.drawn = [];
    }
    panel.scrollTop = keepScroll;
  }

  // -- the settings card: the head row (Run sim, Hide settings), the ETA and why, the fields, the board

  function field(label, input, help, cls) {
    return el('label', { class: 'sim-field' + (cls ? ' ' + cls : '') }, el('span', { class: 'sim-label', text: label }), input, help ? el('span', { class: 'sim-help', text: help }) : null);
  }

  function runCard() {
    const f = S.form || Object.assign({}, M.DEFAULTS);
    const meta = S.meta || {};
    const card = el('section', { class: 'card sim-run' + (S.collapsed ? ' collapsed' : '') });
    const act = activeJob();
    const ro = S.status && S.status.readonly;
    const lock = S.status && S.status.lock;
    const caps = meta.caps || {};
    const runner = meta.runner !== false;
    const blocked = !!act || !!activeId() || !!S.busy || !!ro || !runner;
    const btn = el('button', { type: 'button', class: 'btn primary sim-go', text: S.busy ? S.busy : (act || activeId() ? 'A sim is running…' : 'Run sim'), disabled: blocked,
      title: ro ? 'this editor cannot run a sim (see below)' : !runner ? 'game/tools/sim_run.gd is missing' : 'play the runs now (one sim at a time)',
      onclick: () => { if (App.dirty()) { S.confirm = true; draw(); } else runSim(false); } });
    const head = el('div', { class: 'sim-run-head' },
      el('h2', { text: 'Run a sim' }),
      S.collapsed ? el('span', { class: 'sim-summary', text: `${heroName(f.hero)} · ${f.players} runs, ${workersOf(f)} at once · to ${M.fmtT(f.limit)} · board ${M.boardWords(f)} · ${M.DEATHS[f.death] || f.death} · seed ${f.seed} · bot ${botWords(f.bot)}` }) : null,
      el('span', { class: 'spacer' }),
      btn,
      // pass 80 (lane WATCH): one run of this hero, board, seed and bot played in a PC window (tools/watch.py)
      el('button', { type: 'button', class: 'btn small', text: S.watching ? 'Opening…' : 'Watch', disabled: !!S.watching,
        title: 'watch one run of this hero, board, seed and bot in a game window: the phone view on the left, the numbers, charts and decisions of the bot on the right (one Watch at a time)',
        onclick: watchRun }),
      el('button', { type: 'button', class: 'btn small ghost', text: S.collapsed ? 'Show settings' : 'Hide settings', onclick: () => { S.collapsed = !S.collapsed; saveFold(); draw(); } }));
    card.appendChild(head);
    card.appendChild(el('div', { class: 'sim-eta', id: 'sim-eta' }));
    card.appendChild(el('div', { class: 'sim-why', text: meta.speed_words || '' }));
    if (S.confirm && App.dirty()) {
      card.appendChild(el('div', { class: 'sim-confirm' },
        el('p', { text: 'The map has unsaved changes. The game, and so the sim, plays only the saved map.' }),
        el('div', { class: 'sim-btns' },
          el('button', { type: 'button', class: 'btn primary small', text: 'Save and run', onclick: () => runSim(true) }),
          el('button', { type: 'button', class: 'btn small', text: 'Run the saved map', onclick: () => runSim(false) }),
          el('button', { type: 'button', class: 'btn small ghost', text: 'Back', onclick: () => { S.confirm = false; draw(); } }))));
    }
    if (ro) card.appendChild(el('p', { class: 'sim-warn', text: ro.view_only ? 'This editor was started with --no-jobs: it shows sims but cannot run one. Use the Level Editor that runs the job queue.'
      : `Another Level Editor runs the job queue (${ro.who || '?'}, pid ${ro.pid || '?'}): start the sim from that window, or close it and restart this one.` }));
    if (!runner) card.appendChild(el('p', { class: 'sim-warn', text: 'game/tools/sim_run.gd is not in this checkout: there is nothing to play the runs yet.' }));
    if (lock && !act && !activeId() && (lock.alive === false || !lock.owner_file)) {
      card.appendChild(el('div', { class: 'sim-warn' },
        el('span', { text: lock.owner_file ? `The sim lock was left by a sim that stopped (${lock.who}, pid ${lock.pid}). ` : 'The sim lock is held by an unknown process. ' }),
        el('button', { type: 'button', class: 'btn small', text: 'Release it', onclick: () => releaseLock(!lock.owner_file) })));
    }
    if (!S.collapsed) card.appendChild(settingsBody(f, meta, caps));
    setTimeout(drawEta, 0);
    return card;
  }

  function settingsBody(f, meta, caps) {
    const set = (k, v) => { S.form = Object.assign({}, S.form, { [k]: v }); saveDraft(); drawEta(); };
    const body = el('div', { class: 'sim-run-body' });
    const grid = el('div', { class: 'sim-fields' });
    // the map
    const mid = App.S.mapId || f.map;
    const mp = (meta.maps || []).find((m) => m.id === mid);
    const rev = (meta.map_revs || {})[mid] || {};
    grid.appendChild(el('div', { class: 'sim-field' }, el('span', { class: 'sim-label', text: 'Map' }),
      el('div', { class: 'sim-mapline' }, el('b', { text: mp ? mp.name : mid }), el('span', { class: 'muted small', text: rev.saved ? ` · the saved file (${whenText(rev.saved)})` : ' · the saved file' })),
      App.dirty() ? el('span', { class: 'sim-help warn-text', text: 'Unsaved changes: the sim plays the map as last saved (Run sim offers to save first).' }) : el('span', { class: 'sim-help', text: 'the map open in the editor, as last saved' })));
    // the hero
    const hero = el('select', { class: 'sim-input', onchange: (e) => set('hero', e.target.value) });
    for (const h of meta.heroes || []) hero.appendChild(el('option', { value: h.id, text: h.name + (h.hidden ? ' (hidden in the game)' : ''), selected: h.id === f.hero }));
    grid.appendChild(field('Hero', hero, 'who plays every run'));
    // runs, at once
    const players = el('input', { class: 'sim-input num', type: 'number', min: 1, max: meta.max_players || 100, step: 1, value: f.players,
      onchange: (e) => { set('players', Math.max(1, Math.min(meta.max_players || 100, Math.round(Number(e.target.value) || 10)))); e.target.value = S.form.players; draw(); } });
    grid.appendChild(field('Runs', players, 'played and averaged: more = smoother, longer to wait'));
    const workers = el('select', { class: 'sim-input', onchange: (e) => set('workers', Number(e.target.value)) });
    workers.appendChild(el('option', { value: 0, text: `auto (${autoWorkers(f.players)})`, selected: !(Number(f.workers) > 0) }));
    for (let k = 1; k <= maxWorkers(); k++) workers.appendChild(el('option', { value: k, text: String(k), selected: Number(f.workers) === k }));
    grid.appendChild(field('At once', workers, `side by side; auto = as many as the runs, at most ${maxWorkers()} on this PC (${meta.cores || '?'} logical processors - 2)`));
    // stop at
    const limit = el('input', { class: 'sim-input', type: 'text', value: M.fmtT(f.limit), placeholder: '25:00',
      onchange: (e) => {
        const v = M.parseT(e.target.value);
        if (v == null || v < (meta.limit_min || 30)) { e.target.value = M.fmtT(S.form.limit); App.status('Stop at: a time like 25:00 (at least 0:30)', 'bad'); return; }
        set('limit', Math.min(meta.limit_max || 10800, Math.round(v))); e.target.value = M.fmtT(S.form.limit);
      } });
    grid.appendChild(field('Stop at', limit, 'play time; boss fights and portal waits count (the timeline\'s clock stops in them)'));
    // on death: the policies the runner knows
    const deaths = el('div', { class: 'sim-radios' });
    for (const d of meta.deaths || []) {
      deaths.appendChild(el('label', { class: 'sim-radio', title: d.help || '' },
        el('input', { type: 'radio', name: 'sim-death', value: d.value, checked: d.value === f.death, onchange: () => set('death', d.value) }),
        el('span', { text: d.label })));
    }
    const pending = (meta.deaths_all || []).filter((d) => !d.runner).map((d) => d.label);
    grid.appendChild(el('div', { class: 'sim-field' }, el('span', { class: 'sim-label', text: 'On death' }), deaths,
      pending.length ? el('span', { class: 'sim-help', text: `not in this runner yet: ${pending.join(', ')}` }) : null));
    // seed, note
    const seed = el('input', { class: 'sim-input num', type: 'number', min: 0, step: 1, value: f.seed, onchange: (e) => { set('seed', Math.max(0, Math.round(Number(e.target.value) || 0))); e.target.value = S.form.seed; } });
    grid.appendChild(field('Seed', seed, 'run k plays seed + k - 1: the same seed on the same saved map plays the same runs, as far as the game allows'));
    const note = el('input', { class: 'sim-input', type: 'text', maxlength: 200, value: f.note || '', placeholder: 'e.g. after the stage 2 cap change', onchange: (e) => set('note', e.target.value) });
    grid.appendChild(field('Note', note, 'a few words to find this sim in the history'));
    // the runner's sim mode (lane SIMRUN's fast=): offered only when the runner has it
    if (caps.fast) {
      const fast = el('label', { class: 'sim-radio' },
        el('input', { type: 'checkbox', checked: f.fast !== false, onchange: (e) => set('fast', !!e.target.checked) }),
        el('span', { text: 'skip it (sim mode)' }));
      grid.appendChild(field('Drawing', fast, 'on: the runs draw nothing and play no sound (faster); off: every frame drawn and every sound played as in the game (slower, for a check)'));
    }
    body.appendChild(grid);
    body.appendChild(boardEditor(f, meta, caps));
    body.appendChild(botEditor(f, meta, caps));
    return body;
  }

  // -- pass 80 (lane BOT): the bot (game/tools/bot/Bot.gd): a preset, and any option set over it

  /** The bot in a few words: "Explorer", "Sim (pass 77), skill 0.5". */
  function botWords(b) {
    const bm = (S.meta || {}).bot || {};
    const o = b || {};
    const pre = o.preset || bm.default || 'explorer';
    const p = (bm.presets || []).find((x) => x.key === pre);
    const extra = Object.keys(o).filter((k) => k !== 'preset').map((k) => `${k} ${typeof o[k] === 'boolean' ? (o[k] ? 'on' : 'off') : o[k]}`);
    return (p ? p.label : pre) + (extra.length ? ', ' + extra.join(', ') : '');
  }

  /** A value as the form shows it in a tooltip. */
  function botVal(v) {
    return typeof v === 'boolean' ? (v ? 'on' : 'off') : String(v);
  }

  /** The Bot group: the presets (one press sets the preset and clears what was set over it), then every option with the
   *  value the runs will play: the preset's (plain) or set here (marked, with a × back to the preset's). */
  function botEditor(f, meta, caps) {
    const bm = meta.bot || {};
    const b = Object.assign({}, f.bot || {});
    const pre = b.preset || bm.default || 'explorer';
    const preDef = (bm.presets || []).find((p) => p.key === pre) || { key: pre, label: pre, values: {} };
    const setBot = (nb) => {
      S.form = Object.assign({}, S.form, { bot: nb });
      saveDraft();
      draw();
    };
    const box = el('div', { class: 'sim-board sim-bot' });
    const head = el('div', { class: 'sim-board-head' }, el('span', { class: 'sim-label', text: 'Bot' }));
    for (const p of bm.presets || []) {
      head.appendChild(el('button', { type: 'button', class: 'btn small' + (p.key === pre ? ' on' : ''), text: p.label, title: p.help || '',
        onclick: () => setBot({ preset: p.key }) }));
    }
    const nset = Object.keys(b).filter((k) => k !== 'preset').length;
    head.appendChild(el('span', { class: 'sim-board-total', text: `${preDef.label}${nset ? ` · ${nset} option${nset === 1 ? '' : 's'} set over it` : ''}` }));
    box.appendChild(head);
    if (!caps.bot) box.appendChild(el('p', { class: 'sim-warn small', text: 'This runner has no bot options yet (game/tools/bot/Bot.gd): it plays its own bot, so Run sim refuses a bot setting.' }));
    if (preDef.help) box.appendChild(el('p', { class: 'muted small', text: preDef.help }));
    const grid = el('div', { class: 'sim-bot-fields' });
    for (const k of bm.keys || []) {
      const own = Object.prototype.hasOwnProperty.call(b, k.key);
      const pv = (preDef.values || {})[k.key];
      const v = own ? b[k.key] : pv;
      const change = (nv) => {
        const nb = Object.assign({}, S.form.bot || {}, { preset: pre });
        if (nv === pv) delete nb[k.key]; else nb[k.key] = nv;
        setBot(nb);
      };
      let input;
      if (k.kind === 'bool') {
        input = el('input', { type: 'checkbox', checked: !!v, onchange: (e) => change(!!e.target.checked) });
      } else if (k.kind === 'enum') {
        input = el('select', { class: 'sim-input', onchange: (e) => change(e.target.value) });
        for (const c of k.choices || []) input.appendChild(el('option', { value: c, text: c, selected: c === v }));
      } else {
        input = el('input', { class: 'sim-input num', type: 'number', min: k.lo, max: k.hi, step: k.step || 0.05, value: v,
          onchange: (e) => {
            let n = Number(e.target.value);
            if (!isFinite(n)) n = Number(v);
            change(Math.round(Math.min(k.hi, Math.max(k.lo, n)) * 1000) / 1000);
          } });
      }
      const reset = own ? el('button', { type: 'button', class: 'btn small ghost', text: '×', title: `back to the ${preDef.label} preset's ${botVal(pv)}`,
        onclick: () => { const nb = Object.assign({}, S.form.bot || {}); delete nb[k.key]; setBot(nb); } }) : null;
      grid.appendChild(el('label', { class: 'sim-bot-field' + (own ? ' set' : ''), title: k.help || '' },
        el('span', { class: 'sim-bot-name', text: k.label }), input, reset,
        el('span', { class: 'sim-bot-from', text: own ? `set here (preset ${botVal(pv)})` : 'the preset\'s' })));
    }
    box.appendChild(grid);
    box.appendChild(el('p', { class: 'muted small', text: 'Each run\'s bot plays with these; the decisions it makes (cards, gifts, deals, goals) are written into its run file with their scores and reasons. Hover an option for what it does.' }));
    return box;
  }

  /** The Upgrade board talent by talent: the presets, then each talent's rank (0-6) and form. */
  function boardEditor(f, meta, caps) {
    const box = el('div', { class: 'sim-board' });
    const t = f.talents || {};
    const pre = M.presetOf(t, meta.presets);
    const label = f.board_label || (pre ? pre.label : 'custom');
    const setBoard = (talents, lab, board) => {
      S.form = Object.assign({}, S.form, { talents, board_label: lab, board });
      saveDraft();
      draw();
    };
    const edited = (talents) => {
      const p = M.presetOf(talents, meta.presets);
      setBoard(talents, p ? p.label : 'custom', p && p.key !== 'save' ? p.board : -1);
    };
    const head = el('div', { class: 'sim-board-head' }, el('span', { class: 'sim-label', text: 'Upgrade board' }));
    for (const p of meta.presets || []) {
      head.appendChild(el('button', { type: 'button', class: 'btn small' + (pre && pre.key === p.key ? ' on' : ''), text: p.label,
        title: p.key === 'save' ? `the talents bought in your save on this PC (${meta.save_note || ''})` : `difficulty_probe's ${p.label} board: ${M.boardRanks(p.talents)} ranks, each talent in its usual form`,
        onclick: () => setBoard(Object.assign({}, p.talents), p.label, p.key === 'save' ? -1 : p.board) }));
    }
    head.appendChild(el('span', { class: 'sim-board-total', text: `${label} · ${M.boardRanks(t)} of ${M.MAX_RANK * (meta.talents || []).length || 48} ranks` }));
    box.appendChild(head);
    if (!caps.talents && !(pre && pre.key !== 'save')) {
      box.appendChild(el('p', { class: 'sim-warn small', text: 'This runner plays only the presets none, a quarter, half and full until lane SIMRUN\'s talents= lands: a custom board or your save would not be played as set, so Run sim refuses it.' }));
    }
    const grid = el('div', { class: 'sim-talents' });
    for (const def of meta.talents || []) {
      const picks = String(t[def.id] || '');
      const rank = el('select', { class: 'sim-input tiny', title: 'ranks bought (0-6)', onchange: (e) => {
        const form = picks ? (picks.slice(-1) === 'B' ? 1 : 0) : def.preset_form;
        const next = Object.assign({}, t, { [def.id]: M.setRank(picks, Number(e.target.value), picks ? undefined : form) });
        if (!next[def.id]) delete next[def.id];
        edited(next);
      } });
      for (let r = 0; r <= (def.ranks || M.MAX_RANK); r++) rank.appendChild(el('option', { value: r, text: String(r), selected: r === picks.length }));
      const form = el('select', { class: 'sim-input', disabled: !picks, title: 'the form every rank is bought in', onchange: (e) => {
        if (e.target.value === 'mixed') return;
        edited(Object.assign({}, t, { [def.id]: (e.target.value === '1' ? 'B' : 'A').repeat(picks.length) }));
      } });
      const mixed = /A/.test(picks) && /B/.test(picks);
      if (mixed) form.appendChild(el('option', { value: 'mixed', text: M.picksWords(picks, def.forms), selected: true }));
      def.forms.forEach((fm, i) => form.appendChild(el('option', { value: i, text: fm.name, selected: !mixed && picks.length > 0 && picks[0] === 'AB'[i], title: fm.text })));
      if (!picks) form.appendChild(el('option', { value: '', text: '—', selected: true }));
      grid.appendChild(el('div', { class: 'sim-talent' + (picks ? '' : ' none'), title: `${def.name}: ${def.flavour}\n${def.forms.map((fm) => `${fm.name}: ${fm.text}`).join('\n')}` },
        el('b', { text: def.name }), rank, form));
    }
    box.appendChild(grid);
    return box;
  }

  function drawEta() {
    const box = document.getElementById('sim-eta');
    if (!box || !S.form) return;
    const meta = S.meta || {};
    const f = S.form;
    const sp = (f.fast === false && meta.speed_off ? meta.speed_off : meta.speed) || {};   // the chosen mode's measured speed
    const k = workersOf(f);
    const eta = M.etaSeconds(Object.assign({}, f, { workers: k }), sp, meta.cores, meta.snapshot && meta.snapshot.exists ? 20 : 120);
    box.textContent = `About ${M.fmtDuration(eta)} for ${f.players} run${f.players === 1 ? '' : 's'} of ${M.fmtT(f.limit)}, ${k} at once` +
      (f.death !== 'keep' ? ', if every run lasts that long (a run that ends at a death takes less)' : '') +
      (meta.snapshot && !meta.snapshot.exists ? ' (the first sim also copies the game: about a minute more)' : '') +
      (sp.measured ? '' : ' (a first guess until a sim has been measured)') + '.';
  }

  // -- the progress

  function progressCard() {
    const job = activeJob();
    const p = S.status && S.status.progress;
    if (!job && !(p && activeId())) return null;
    const card = el('section', { class: 'card sim-progress' });
    card.appendChild(el('div', { class: 'sim-run-head' }, el('h2', { text: job && job.state === 'queued' ? 'Sim queued' : 'Sim running' }), el('span', { class: 'spacer' }),
      el('button', { type: 'button', class: 'btn small danger', text: 'Cancel', title: 'stop every run now; the runs already finished stay as a partial result', onclick: cancelSim }),
      el('button', { type: 'button', class: 'btn small ghost', text: 'Open in Jobs', onclick: () => App.switchTab('jobs') })));
    const body = el('div', { class: 'sim-prog-body', id: 'sim-prog-body' });
    card.appendChild(body);
    fillProgress(body);
    return card;
  }

  function drawProgress() {
    const body = document.getElementById('sim-prog-body');
    if (body) fillProgress(body);
    else if (isActive()) draw();
  }

  function fillProgress(body) {
    clear(body);
    const job = activeJob();
    const p = (S.status && S.status.progress) || null;
    if (!p) {
      body.appendChild(el('p', { class: 'muted small', text: job && job.state === 'queued' ? 'Waiting for its turn on the sim lane.' : 'Starting…' }));
      return;
    }
    const words = { starting: 'starting', waiting: 'waiting for the sim lock', syncing: 'copying the game to the snapshot', importing: 'the snapshot imports what changed', running: 'playing', aggregating: 'averaging' };
    const total = p.total || 0, done = p.done || 0;
    body.appendChild(el('div', { class: 'sim-prog-line' },
      el('b', { text: `${done} of ${total} runs done` }),
      el('span', { class: 'muted', text: ` · ${words[p.state] || p.state} · ${M.fmtT(p.elapsed_s)} so far${p.eta_s != null && p.state !== 'aggregating' ? ` · about ${M.fmtDuration(p.eta_s)} left (from the runs' own pace)` : ''}` })));
    if (p.lock_wait) body.appendChild(el('p', { class: 'sim-warn small', text: p.lock_wait.replace(/^sim: /, '') }));
    body.appendChild(el('div', { class: 'jbar sim-bar' }, el('i', { style: `width:${total ? Math.round((100 * done) / total) : 0}%` })));
    const limit = (p.settings || {}).limit || 1500;
    const list = el('div', { class: 'sim-runs-live' });
    for (const r of p.players || []) {
      if (r.state === 'queued') continue;
      const frac = Math.max(0, Math.min(1, (r.state === 'done' ? (r.end_t || r.t) : r.t) / limit));
      const info = r.info || {};
      const tail = r.state === 'running' ? `${M.fmtT(r.t)}${info.level ? ' · level ' + info.level : ''}${info.deaths && info.deaths !== '0' ? ' · ' + info.deaths + ' death' + (info.deaths === '1' ? '' : 's') : ''}`
        : r.state === 'done' ? `${endWords(r.end_reason)} at ${M.fmtT(r.end_t)}` : `failed: ${r.problem || '?'}`;
      list.appendChild(el('div', { class: 'sim-run-live ' + r.state, title: `run ${r.k} (seed ${r.seed}) · ${M.fmtT(r.wall_s)} of wall time` },
        el('span', { class: 'k', text: `run ${r.k}` }),
        el('span', { class: 'track' }, el('i', { style: `width:${Math.round(frac * 100)}%` })),
        el('span', { class: 'v', text: tail })));
    }
    if (list.children.length) body.appendChild(list);
    const q = (p.players || []).filter((r) => r.state === 'queued').length;
    if (q) body.appendChild(el('p', { class: 'muted small', text: `${q} more waiting for a free place.` }));
  }

  function endWords(r) {
    const s = String(r || '');
    if (s === 'limit') return 'reached the stop';
    if (s === 'death') return 'died';
    if (s.startsWith('stuck')) return `stuck (${s.split(':')[1] || '?'})`;
    return s || 'ended';
  }

  // -- the history

  function historyCard() {
    const det = el('details', { class: 'card sim-history', open: S.histOpen });
    det.addEventListener('toggle', () => { S.histOpen = det.open; saveFold(); });
    det.appendChild(el('summary', {}, el('b', { text: 'History' }), el('span', { class: 'muted small', text: ` · the last ${(S.meta && S.meta.history_keep) || 10} sims (a kept one is never removed) · ${S.history.length} here` })));
    if (!S.history.length) { det.appendChild(el('p', { class: 'muted small', text: 'No sims yet.' })); return det; }
    const list = el('div', { class: 'sim-hist-list' });
    for (const h of S.history) {
      const st = h.settings || {};
      const cur = h.id === S.currentId, cmp = h.id === S.compareId;
      const badge = h.state === 'done' ? null : el('span', { class: 'sim-badge ' + h.state, text: h.state === 'partial' ? `partial ${h.players_done}/${h.players_total}` : h.state });
      list.appendChild(el('div', { class: 'sim-hist' + (cur ? ' current' : '') + (cmp ? ' compared' : '') },
        el('div', { class: 'sim-hist-main' },
          el('b', { text: simLabel(h) }), badge, h.synthetic ? el('span', { class: 'sim-badge synthetic', text: 'made up', title: 'made-up runs (a test of the page), not the game' }) : null,
          h.kept ? el('span', { class: 'sim-badge kept', text: 'kept' }) : null,
          el('span', { class: 'muted small', text: ` board ${h.board_words || M.boardLabel(st.board)} · ${h.death_words || st.death} · seed ${st.seed}${h.bot_words ? ' · bot ' + h.bot_words : ''}${h.drawn ? ' · everything drawn' : ''}${h.map_rev && h.map_rev.sha ? ' · map ' + h.map_rev.sha.slice(0, 7) : ''}${st.note ? ' · “' + st.note + '”' : ''}` })),
        el('div', { class: 'sim-btns' },
          el('button', { type: 'button', class: 'btn small' + (cur ? ' primary' : ''), text: cur ? 'Shown' : 'Show', disabled: !h.has_result || cur, onclick: async () => { await show(h.id); draw(); } }),
          el('button', { type: 'button', class: 'btn small' + (cmp ? ' on' : ''), text: cmp ? 'Compared' : 'Compare', disabled: !h.has_result || cur, title: 'its lines dashed grey on the charts of the sim shown', onclick: () => setCompare(cmp ? '' : h.id) }),
          el('button', { type: 'button', class: 'btn small ghost', text: h.kept ? 'Unkeep' : 'Keep', title: h.kept ? 'it may be removed once 10 newer sims exist' : 'never removed from the history', onclick: () => keepSim(h.id, !h.kept) }),
          el('button', { type: 'button', class: 'btn small ghost danger', text: 'Delete', disabled: h.state === 'running' || h.state === 'queued', onclick: () => deleteSim(h.id) }))));
    }
    det.appendChild(list);
    return det;
  }

  function whenText(iso) {
    const d = new Date(iso);
    if (isNaN(d.getTime())) return String(iso || '');
    const hm = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
    return d.toDateString() === new Date().toDateString() ? `today ${hm}` : `${d.getMonth() + 1}/${d.getDate()} ${hm}`;
  }

  // -- the header, the tiles, the runs

  function emptyCard() {
    return el('section', { class: 'card sim-empty' },
      el('h2', { text: 'No sim to show yet' }),
      el('p', { text: 'Choose the settings above and press Run sim. The game plays the saved map that many times with a bot (it kites the crowd, gathers gems, steps out of warning rings, picks cards as a sensible player would, takes chests, walks to the boss\'s chest and the portal; as the Explorer, the default, it also explores the map, takes the Totem Poles\' gifts, breaks barrels, chases power-ups and uses the structures, the Shop and the Stranger: the Bot group above), and these charts show the average of every second of play: DPS, HP, deaths, how hard each second is (health lost, keeping up with the crowd, what is close, what hurts), coins, damage by source, kills by creature, level, XP and the build.' }),
      el('p', { class: 'muted small', text: 'The sim copies the game into its own folder first, so you can keep editing and saving while it runs: it plays what was saved when it started.' }));
  }

  function headCard() {
    const r = S.current;
    const meta = r.meta || {};
    const st = r.settings || {};
    const card = el('section', { class: 'card sim-head' });
    const played = meta.sim_mode === false ? Object.assign({}, st, { fast: false }) : st;   // what the runs played
    const title = el('div', { class: 'sim-head-top' }, el('h2', { text: M.settingsLine(played, meta.hero_name || (r.names || {})[st.hero]) }));
    if (meta.partial) title.appendChild(el('span', { class: 'sim-badge partial', text: `partial: ${meta.players_done} of ${meta.players_total} runs` }));
    if (meta.synthetic) title.appendChild(el('span', { class: 'sim-badge synthetic', text: 'MADE-UP RUNS: a test of the page, not the game' }));
    card.appendChild(title);
    const rev = meta.map_rev || {};
    const cur = ((S.meta || {}).map_revs || {})[st.map] || {};
    const bits = [`${rev.name || st.map} as saved ${rev.saved ? whenText(rev.saved) : '?'}${rev.sha ? ' (' + rev.sha.slice(0, 7) + ')' : ''}`];
    if (meta.version) bits.push(`game ${meta.version}`);
    if (meta.started) bits.push(`ran ${whenText(meta.started)}`);
    if (meta.wall_s) bits.push(`took ${M.fmtDuration(meta.wall_s)}`);
    bits.push(`${st.workers} at once, ${st.fps} fps`);
    if (meta.unlocks === 'all') bits.push('every item unlocked');
    if (meta.assists) bits.push(`the bot was put on the portal or the boss chest ${meta.assists} time${meta.assists === 1 ? '' : 's'}`);
    if (st.note) bits.push('“' + st.note + '”');
    card.appendChild(el('div', { class: 'muted small', text: bits.join(' · ') }));
    if (st.talents && Object.keys(st.talents).length) {
      const defs = (S.meta || {}).talents || [];
      const words = defs.filter((d) => st.talents[d.id]).map((d) => `${d.name} ${st.talents[d.id].length} ${M.picksWords(st.talents[d.id], d.forms)}`);
      card.appendChild(el('div', { class: 'muted small', text: 'Board: ' + (words.join(' · ') || 'none') }));
    }
    if ((meta.board_differs || []).length) card.appendChild(el('div', { class: 'sim-warn small', text: `Some runs played another board than asked (an older runner?): ${meta.board_differs.join('; ')}` }));
    // pass 80 (lane BOT): the bot and what it did with the map, the means over the runs
    const sb = (r.bot || {}).summary;
    if (sb || st.bot) {
      const did = sb ? ` · a run used ${sb.totems} Totem Poles (${sb.totems_20} by 20:00), broke ${sb.barrels} barrels, used ${sb.structures} other structures, took ${sb.powerups} power-ups, ${sb.shop} shop buys, ${sb.stranger} deals with the Stranger, walked ${M.fmtNum(sb.metres)} m and saw ${Math.round((sb.seen || 0) * 100)}% of the map (means)` : '';
      card.appendChild(el('div', { class: 'muted small', text: `Bot: ${botWords(st.bot)}${did}` }));
    }
    if (rev.sha && cur.sha && rev.sha !== cur.sha) card.appendChild(el('div', { class: 'sim-warn small', text: `The map has been saved since this sim (now ${cur.sha.slice(0, 7)}, ${whenText(cur.saved)}): run it again to see the change.` }));
    const sel = el('select', { class: 'sim-input', onchange: (e) => setCompare(e.target.value) });
    sel.appendChild(el('option', { value: '', text: 'nothing' }));
    for (const h of S.history) if (h.has_result && h.id !== S.currentId) sel.appendChild(el('option', { value: h.id, text: simLabel(h) + (h.settings && h.settings.note ? ' · ' + h.settings.note : ''), selected: h.id === S.compareId }));
    card.appendChild(el('div', { class: 'sim-compare' },
      el('span', { class: 'sim-label', text: 'Compare with' }), sel,
      S.compare ? el('span', { class: 'muted small' }, SimPlot.keyLine(M.COMPARE, M.COMPARE_DASH), ` its lines dashed grey: ${M.settingsLine(S.compare.settings, (S.compare.meta || {}).hero_name)}`) : null));
    return card;
  }

  function tilesRow() {
    const row = el('div', { class: 'sim-tiles' });
    for (const t of M.tiles(S.current)) row.appendChild(el('div', { class: 'sim-tile' }, el('div', { class: 'sim-tile-label', text: t.label }), el('div', { class: 'sim-tile-value', text: t.value }), el('div', { class: 'sim-tile-note', text: t.note })));
    return row;
  }

  function runsTable() {
    const r = S.current;
    const det = el('details', { class: 'card sim-runs' }, el('summary', { text: `The ${r.players.length} runs one by one` }));
    const tb = el('table', { class: 'sim-table' });
    tb.appendChild(el('thead', {}, el('tr', {}, ...['run', 'seed', 'ended', 'at', 'deaths', 'revives', 'level', 'kills', 'coins', 'the map', 'build at the end'].map((h) => el('th', { text: h })))));
    const body = el('tbody');
    const bots = {};
    for (const b of ((r.bot || {}).players || [])) bots[b.k] = b;
    for (const p of r.players) {
      body.appendChild(el('tr', { class: p.ok ? '' : 'bad' },
        el('td', { text: String(p.k) }), el('td', { text: String(p.seed) }),
        el('td', { text: p.ok ? endWords(p.end_reason) : `failed: ${p.problem || '?'}` }), el('td', { text: M.fmtT(p.end_t) }),
        el('td', { text: p.deaths == null ? '–' : String(p.deaths) }), el('td', { text: String(p.revives || 0) }),
        el('td', { text: p.level == null ? '–' : String(p.level) }), el('td', { text: M.fmtNum(p.kills) }), el('td', { text: M.fmtNum(p.gold) }),
        el('td', { text: bots[p.k] ? `${bots[p.k].totems} totems · ${bots[p.k].barrels} barrels · ${bots[p.k].structures} structures · ${bots[p.k].powerups} power-ups` : '–' }),
        el('td', { class: 'build', text: p.build || '' })));
    }
    tb.appendChild(body);
    det.appendChild(el('div', { class: 'sim-table-wrap wide' }, tb));
    det.appendChild(el('p', { class: 'muted small', text: 'A run "reached the stop" when it played to the stop time; "died" when a death ended it (no revive left, or the setting says the first death ends it); "stuck" when a screen stayed up too long or the run took too long on the PC (the bot\'s watchdog wrote what it had).' }));
    return det;
  }

  // ------------------------------------------------------------------ the charts (pass 78: drawn by sim_plot.js)

  // the hooks the shared drawing calls (tools/level_editor/sim_plot.js: the same charts in analytics/dashboard.html)
  S.toggleRaw = () => { S.raw = !S.raw; draw(); };
  S.toggleTable = (id) => { if (S.tables.has(id)) S.tables.delete(id); else S.tables.add(id); draw(); };
  S.download = (name, text) => U.download(name, text);
  S.csvName = (c) => `sim_${S.currentId}_${c.id}.csv`;

  /** The charts in their sections (Garry's order): sim_plot.js draws them. */
  function drawCharts(container) {
    SimPlot.drawCharts(container, S);
  }

  // a resize (or the panel's scrollbar appearing) changes the plots' widths: draw them again at the new widths
  let resizeT = 0;
  window.addEventListener('resize', () => {
    if (App.S.tab !== 'sim' || !S.drawn.length) return;
    clearTimeout(resizeT);
    resizeT = setTimeout(() => SimPlot.replot(S), 150);
  });

  return { render, draw, poll, S };
})();
