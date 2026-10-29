'use strict';
// Pass 111, lane WANTED: the Wanted tab. Garry: "Make a nice config for me to be able to set it up easily in LevelEditor.
// Make it so I can set up the weights of each different task probability. Always a choice of 3. I should be able to set up
// some difficulty score for it. It should also scale with Player progression ... Have it as a separate tab in the
// LevelEditor (and just for lols add a simulated visual wanted poster UI imitation on the same page that I can 'roll'
// myself)". Pass 112: the posters float in over the run right after the hero's descent (ui/BountyPosters.gd), no longer a
// full-screen board before the run. The page edits game/content/wanted/wanted.json (the game's WantedBoard.gd reads it at boot): the board's
// switches, the reward formula with a live table, and every task type (on, weight with its resulting chances, difficulty,
// its numbers per stage, its words). Beside it, "Try the board": Roll draws three posters with the unsaved config in the
// browser (wanted_model.js mirrors the game's roll) from the map's own timeline (the Timeline tab's, unsaved edits too),
// drawn as the game's posters with the real stills. Save (or Ctrl+S on this tab) writes the file with a backup.
const Wanted = (() => {
  const { el, clear } = U;
  const M = WantedModel;
  const ART = '/api/wanted/art/';
  const S = {
    data: null, failed: null, loading: false, items: null, heroes: null, currencies: ['gold'],
    draft: null, base: null, mtime: null, history: [], saving: false, msg: null,
    open: {},          // the task cards opened
    sim: { stage: 0, hero: '', P: 0, metAll: true, seenAll: true, unlocks: true, seed: 0, posters: [], picked: -1, exStage: 0 },
  };

  // ------------------------------------------------------------------ data

  async function getJSON(url) { const r = await fetch(url, { cache: 'no-store' }); if (!r.ok) throw new Error(`${url}: HTTP ${r.status}`); return r.json(); }
  function load(force) {
    if (S.loading || (S.data && !force)) return;
    S.loading = true;
    Promise.all([getJSON('/api/wanted'), getJSON('/api/items'), getJSON('/api/heroes')]).then(([w, items, heroes]) => {
      S.data = w; S.items = items; S.heroes = heroes; S.failed = null; S.loading = false;
      if (!w.ok) S.failed = w.error || 'the config could not be read';
      const json = w.json || { tasks: [] };
      S.base = JSON.parse(JSON.stringify(json));
      S.draft = JSON.parse(JSON.stringify(json));
      S.mtime = w.mtime;
      S.history = [];
      if (!S.sim.hero) { const h = playable()[0]; S.sim.hero = h ? h.id : ''; }
      roll(true);
      redraw();
    }).catch((e) => { S.failed = e.message; S.loading = false; redraw(); });
    // pass 111 (lane SKINS' registry): the currencies a reward may be paid in (gold alone until there are more)
    getJSON('/api/currencies').then((cs) => { const list = Array.isArray(cs) ? cs : (cs && cs.currencies) || []; const ids = list.map((c) => c.id).filter(Boolean); if (ids.length) { S.currencies = ids; redraw(); } }).catch(() => {});
  }
  const dirty = () => S.draft != null && JSON.stringify(S.draft) !== JSON.stringify(S.base);
  const redraw = () => { if (typeof App !== 'undefined' && App.S.tab === 'wanted') App.render('tab'); };
  const cfg = () => M.normalized(S.draft || {});
  const playable = () => (S.heroes || []).filter((h) => !h.hidden_in_play);

  function edit(fn, quiet) {
    const before = JSON.stringify(S.draft);
    fn(S.draft);
    if (JSON.stringify(S.draft) === before) return;
    S.history.push(before);
    if (S.history.length > 200) S.history.shift();
    if (!quiet) redraw();
  }
  function undo() { if (!S.history.length) return; S.draft = JSON.parse(S.history.pop()); redraw(); }
  function revert() { S.draft = JSON.parse(JSON.stringify(S.base)); S.history = []; redraw(); }

  async function save() {
    if (!S.draft || S.saving) return;
    const iss = M.issues(cfg());
    if (iss.errors.length) { App.status(`Cannot save the board: ${iss.errors.join(' · ')}`, 'bad'); return; }
    if (!dirty()) { App.status('Nothing to save'); return; }
    S.saving = true; redraw();
    App.status('Saving the Bounty Board…', 'busy');
    const r = await fetch('/api/wanted/save', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ json: S.draft, base_mtime: S.mtime }) });
    let data; try { data = await r.json(); } catch (_) { data = { ok: false, error: `HTTP ${r.status}` }; }
    S.saving = false;
    if (r.status === 409) { S.msg = 'wanted.json changed on disk since this page read it: Reload to take the file, or Save again to keep yours'; S.mtime = data.mtime; App.status(S.msg, 'bad'); redraw(); return; }
    if (!data.ok) { App.status(`Save failed: ${data.error}${r.status === 404 ? ' (restart the editor: the route is new in pass 111)' : ''}`, 'bad'); redraw(); return; }
    S.base = JSON.parse(JSON.stringify(S.draft)); S.mtime = data.mtime; S.msg = null;
    App.status(data.unchanged ? 'Nothing changed on disk' : `Saved ${data.file}${data.backup ? ' (backup ' + data.backup + ')' : ''} · the game reads it when it starts`, 'good');
    redraw();
  }
  function reload() { S.data = null; S.msg = null; load(true); }

  // ------------------------------------------------------------------ the context the simulator rolls from

  function ctxNow() {
    const tl = (typeof App !== 'undefined' && App.S.tl) || {};
    const stages = typeof App !== 'undefined' && App.stageList ? App.stageList() : [];
    const hero = (S.heroes || []).find((h) => h.id === S.sim.hero) || playable()[0] || {};
    const k = Math.min(S.sim.stage, Math.max(stages.length - 1, 0));
    return M.contextFrom({ tl, map: (typeof App !== 'undefined' && App.S.mapId) || 'red_canyon', stage: k, stages,
      creatures: (typeof App !== 'undefined' && App.S.enemies) || [], weapons: (S.items && S.items.weapons) || [],
      lines: (S.items && S.items.lines) || [], hero, P: S.sim.P, beaten: k < S.sim.P,
      metAll: S.sim.metAll, seenAll: S.sim.seenAll, unlocksDone: S.sim.unlocks,
      // pass 113 (lane TASKS): the passive items (item_level, heal_item) and the heal sources (tasks.js loads them)
      passives: (S.items && S.items.passives) || [], sources: (typeof TaskPics !== 'undefined' && TaskPics.S.sources) || null });
  }

  function roll(quiet) {
    if (!S.draft) return;
    S.sim.seed = (Math.random() * 1e9) >>> 0;
    S.sim.posters = M.roll(cfg(), ctxNow(), M.mulberry32(S.sim.seed));
    S.sim.picked = -1;
    if (!quiet) redraw();
  }

  // ------------------------------------------------------------------ the page

  function render(panel) {
    const scroll = panel.scrollTop;
    const active = panel.contains(document.activeElement) ? document.activeElement.dataset.path : null;
    clear(panel);
    load();
    const page = el('div', { class: 'wtd' });
    if (S.failed && !S.draft) {
      page.appendChild(el('p', { class: 'ferr bad', text: `Could not read the Bounty Board: ${S.failed} (restart the editor: the /api/wanted route is new in pass 111)` }));
      panel.appendChild(page); return;
    }
    if (!S.draft) { page.appendChild(el('p', { class: 'muted', text: 'Loading the Bounty Board…' })); panel.appendChild(page); return; }
    page.appendChild(head());
    page.appendChild(el('p', { class: 'lead wtd-lead', html: 'At the start of a stage run, right after the hero\'s descent (from a player\'s <b>second</b> run on), <b>three Wanted posters</b> float in over the paused game on strings: the player taps one to take it (it is stamped and flies into the HUD\'s bounty plate), or taps No bounty (they blow away). Each poster is a <b>task type</b> drawn by its <b>weight</b>; its number (kills, seconds, level...) is rolled in that stage\'s range, which grows with <b>progression</b> (the stages the player has beaten); its <b>difficulty</b> is where that number fell between the range\'s easy and hard end; its <b>gold</b> comes from the difficulty. Done, it pays at the run\'s end. Only creatures the player has met and items he has seen and unlocked can be targets. Roll the posters on the right to see them as a player would.' }));
    const iss = M.issues(cfg());
    if (S.msg) page.appendChild(el('div', { class: 'ferr warn' }, el('span', { text: S.msg + ' ' }), el('button', { class: 'btn small', type: 'button', text: 'Reload', onclick: reload })));
    if (iss.errors.length || iss.warnings.length) {
      const box = el('div', { class: 'wtd-issues' });
      for (const e of iss.errors) box.appendChild(el('div', { class: 'ferr bad', text: e }));
      for (const w of iss.warnings) box.appendChild(el('div', { class: 'ferr warn', text: w }));
      page.appendChild(box);
    }
    const ctx = ctxNow();
    const grid = el('div', { class: 'wtd-grid' });
    const left = el('section', { class: 'wtd-cfg' });
    left.appendChild(boardCard());
    left.appendChild(rewardCard());
    left.appendChild(tasksCard(ctx));
    grid.appendChild(left);
    grid.appendChild(simPane(ctx));
    page.appendChild(grid);
    panel.appendChild(page);
    panel.scrollTop = scroll;
    if (active) { const again = panel.querySelector(`[data-path="${CSS.escape(active)}"]`); if (again) again.focus({ preventScroll: true }); }
  }

  function head() {
    const d = dirty();
    return el('div', { class: 'wtd-head' },
      el('h2', { text: 'Bounty Board' }),
      el('code', { class: 'wtd-file', text: (S.data && S.data.file) || 'game/content/wanted/wanted.json' }),
      d ? el('span', { class: 'dirty-dot', text: '●', title: 'unsaved changes' }) : null,
      el('span', { class: 'spacer' }),
      el('button', { class: 'btn small', type: 'button', text: 'Undo', disabled: !S.history.length, onclick: undo }),
      el('button', { class: 'btn small', type: 'button', text: 'Revert', disabled: !d, onclick: revert }),
      el('button', { class: 'btn small primary', type: 'button', text: S.saving ? 'Saving…' : 'Save board', disabled: !d || S.saving, title: 'write wanted.json (a backup first; Ctrl+S on this tab). The game reads it when it starts.', onclick: save }));
  }

  // a number box that commits on change (Enter or leaving it)
  function numBox(value, set, o) {
    const opt = o || {};
    const inp = el('input', { type: 'number', class: 'num ' + (opt.cls || 'short'), value: value == null ? '' : value, step: opt.step || 'any', min: opt.min != null ? opt.min : null, max: opt.max != null ? opt.max : null, title: opt.title || '', 'data-path': opt.path || '' });
    inp.addEventListener('change', () => { const v = inp.value === '' ? null : Number(inp.value); if (v == null || isFinite(v)) set(v); });
    inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') inp.blur(); });
    return inp;
  }
  function check(value, set, label, path) {
    const cb = el('input', { type: 'checkbox', checked: !!value, 'data-path': path || '' });
    cb.addEventListener('change', () => set(cb.checked));
    return el('label', { class: 'cb' }, cb, el('span', { text: label }));
  }
  function row(label, help, ...ctl) {
    return el('div', { class: 'frow' }, el('label', { class: 'flabel', text: label, title: help || '' }), el('div', { class: 'fctl' }, ...ctl, help ? el('span', { class: 'hint wtd-hint', text: help }) : null));
  }
  function card(title, sub, ...body) {
    return el('div', { class: 'wtd-card' }, el('div', { class: 'wtd-card-head' }, el('h3', { text: title }), sub ? el('span', { class: 'muted small', text: sub }) : null), ...body);
  }

  function boardCard() {
    const c = cfg();
    return card('The posters', 'who sees them and how many',
      row('On', 'off: the game never shows the posters', check(c.enabled !== false, (v) => edit((d) => { d.enabled = v; }), 'Show the Wanted posters after the descent', 'enabled')),
      row('Posters', 'how many posters to pick from (Garry: always 3; the screen has room for 1 to 3)', numBox(c.choices, (v) => edit((d) => { d.choices = Math.max(1, Math.min(3, Math.round(v || 3))); }), { min: 1, max: 3, step: 1, path: 'choices' })),
      row('Re-rolls', 'how many times a player may roll the posters again before choosing (a Re-roll button beside No bounty; 0 = never)', numBox(c.rerolls, (v) => edit((d) => { d.rerolls = Math.max(0, Math.round(v || 0)); }), { min: 0, step: 1, path: 'rerolls' })),
      row('Opens after', 'finished runs before the posters show: 1 = from the second run on (a first-time player never sees them)', numBox((c.unlock || {}).runs, (v) => edit((d) => { d.unlock = Object.assign({}, d.unlock, { runs: Math.max(1, Math.round(v || 1)) }); }), { min: 1, step: 1, path: 'unlock.runs' })),
      row('Targets', 'what a poster may name', check(c.creatures_met_only !== false, (v) => edit((d) => { d.creatures_met_only = v; }), 'only creatures the player has met', 'creatures_met_only'),
        check(c.items_seen_only !== false, (v) => edit((d) => { d.items_seen_only = v; }), 'only items he has seen (his own gun always)', 'items_seen_only')),
      row('Numbers grow', 'each stage beaten makes every range this much bigger (a lower-is-harder number this much smaller): 0.15 = +15% a stage beaten', numBox((c.progress || {}).param_growth, (v) => edit((d) => { d.progress = Object.assign({}, d.progress, { param_growth: Math.max(0, v || 0) }); }), { min: 0, step: 0.05, path: 'progress.param_growth' }), el('span', { class: 'muted small', text: 'per stage beaten' })));
  }

  function rewardCard() {
    const c = cfg();
    const rw = c.reward || {};
    const set = (k) => (v) => edit((d) => { d.reward = Object.assign({}, d.reward, { [k]: Math.max(0, v == null ? 0 : v) }); });
    const sm = Array.isArray(rw.stage_mult) ? rw.stage_mult : [1, 1.25, 1.5];
    const smBoxes = [0, 1, 2].map((i) => el('span', { class: 'wtd-sm' }, el('small', { text: `S${i + 1}` }), numBox(sm[i] != null ? sm[i] : sm[sm.length - 1], (v) => edit((d) => {
      const arr = (Array.isArray((d.reward || {}).stage_mult) ? d.reward.stage_mult : [1, 1.25, 1.5]).slice();
      while (arr.length < 3) arr.push(arr[arr.length - 1] || 1);
      arr[i] = Math.max(0, v == null ? 1 : v);
      d.reward = Object.assign({}, d.reward, { stage_mult: arr });
    }), { min: 0, step: 0.05, path: `reward.stage_mult.${i}` })));
    // the live table: difficulty (rows) x stages beaten (columns), for the chosen stage
    const k = S.sim.exStage;
    const tbl = el('table', { class: 'wtd-ex' });
    tbl.appendChild(el('tr', {}, el('th', { text: 'difficulty' }), ...[0, 1, 2, 3].map((p) => el('th', { text: `${p} stage${p === 1 ? '' : 's'} beaten` }))));
    for (const d of [1, 2, 3, 4, 5]) {
      tbl.appendChild(el('tr', {}, el('td', {}, skulls(d, 'wtd-ex-sk')), ...[0, 1, 2, 3].map((p) => el('td', { class: 'wtd-gold', text: M.rewardFor(c, d, p, k).toLocaleString('en-US') }))));
    }
    const stSel = el('select', { 'data-path': 'ex.stage' });
    for (const i of [0, 1, 2]) stSel.appendChild(el('option', { value: i, text: `on Stage ${i + 1}`, selected: i === k }));
    stSel.addEventListener('change', () => { S.sim.exStage = Number(stSel.value); redraw(); });
    return card('Reward', 'what a poster pays when done',
      el('p', { class: 'wtd-formula', html: 'gold = (<b>base</b> + <b>per point</b> × difficulty) × (1 + <b>growth</b> × stages beaten) × <b>stage ×</b>, rounded to <b>round</b>' }),
      row('Base', 'gold every poster pays', numBox(rw.base, set('base'), { min: 0, step: 5, path: 'reward.base' })),
      row('Per point', 'gold per difficulty point (a 5-skull poster pays 5 of these)', numBox(rw.per_point, set('per_point'), { min: 0, step: 5, path: 'reward.per_point' })),
      row('Growth', 'each stage beaten adds this share: 0.5 = +50% a stage beaten', numBox(rw.progress_growth, set('progress_growth'), { min: 0, step: 0.05, path: 'reward.progress_growth' })),
      row('Stage ×', 'a later stage pays more for the same difficulty', ...smBoxes),
      row('Round', 'the gold is rounded to this', numBox(rw.round, set('round'), { min: 1, step: 1, path: 'reward.round' })),
      row('Paid in', 'the currency the posters pay (gold; a currency the game does not have is paid as gold)', curSelect(rw.currency || 'gold')),
      el('div', { class: 'wtd-ex-head' }, el('span', { class: 'muted small', text: 'What a poster pays' }), stSel),
      tbl);
  }

  function curSelect(cur) {
    const sel = el('select', { 'data-path': 'reward.currency' });
    const ids = S.currencies.includes(cur) ? S.currencies : S.currencies.concat([cur]);
    for (const id of ids) sel.appendChild(el('option', { value: id, text: id, selected: id === cur }));
    sel.addEventListener('change', () => edit((d) => { d.reward = Object.assign({}, d.reward, { currency: sel.value }); }));
    return sel;
  }

  function skulls(d, cls) {
    const n = M.skullsOf(d);
    const box = el('span', { class: cls || 'wtd-skulls' });
    for (let i = 0; i < 5; i++) box.appendChild(el('img', { src: ART + 'badges/skull.png', class: i < n ? 'on' : 'off', alt: '' }));
    return box;
  }

  function tasksCard(ctx) {
    const c = cfg();
    const ch = M.typeChances(c, ctx);
    const hero = (S.heroes || []).find((h) => h.id === S.sim.hero);
    const tbl = el('div', { class: 'wtd-tasks' });
    tbl.appendChild(el('div', { class: 'wtd-trow wtd-thead' }, el('span', { text: 'on' }), el('span', { text: 'task' }), el('span', { text: 'weight' }),
      el('span', { text: 'chance', title: 'first: its share of the weight among the types that can be posted; board: the chance it is one of the posters (exact, the draws without putting back)' }),
      el('span', { text: 'difficulty easy → hard' }), el('span', { text: '' })));
    for (const type of M.TYPE_ORDER) tbl.appendChild(taskRow(type, c, ch, ctx));
    return card('Task types', `chances for Stage ${ctx.stage + 1} with ${hero ? hero.name : 'the hero'} and the simulator's switches; "—" cannot be posted there`, tbl);
  }

  function setTask(type, fn) {
    edit((d) => {
      if (!Array.isArray(d.tasks)) d.tasks = [];
      let t = d.tasks.find((x) => x && x.type === type);
      if (!t) { t = { type, on: true, weight: 0, difficulty: [1, 2] }; d.tasks.push(t); }
      fn(t);
    });
  }

  function taskRow(type, c, ch, ctx) {
    const tc = M.taskCfg(c, type);
    const info = M.TYPE_INFO[type];
    const has = Object.keys(tc).length > 0;
    const on = has && tc.on !== false;
    const w = has ? Number(tc.weight || 0) : 0;
    const chance = ch[type];
    const open = !!S.open[type];
    const dif = Array.isArray(tc.difficulty) ? tc.difficulty : [1, 2];
    const slider = el('input', { type: 'range', min: 0, max: 30, step: 1, value: Math.min(30, w), class: 'wtd-w', 'data-path': `t.${type}.weight.r` });
    const wnum = numBox(w, (v) => setTask(type, (t) => { t.weight = Math.max(0, v || 0); }), { min: 0, step: 1, path: `t.${type}.weight`, cls: 'tiny' });
    slider.addEventListener('input', () => { wnum.value = slider.value; });
    slider.addEventListener('change', () => setTask(type, (t) => { t.weight = Number(slider.value); }));
    const cb = el('input', { type: 'checkbox', checked: on, 'data-path': `t.${type}.on` });
    cb.addEventListener('change', () => setTask(type, (t) => { t.on = cb.checked; }));
    const bar = (v, cls) => el('span', { class: 'wtd-bar ' + cls }, el('i', { style: `width:${Math.round(Math.min(1, v) * 100)}%` }), el('b', { text: `${(v * 100).toFixed(v < 0.1 ? 1 : 0)}%` }));
    const chanceCell = chance ? el('span', { class: 'wtd-chance' }, bar(chance.first, 'first'), bar(chance.board, 'board'))
      : el('span', { class: 'muted small', text: on && w > 0 ? '— (no target here)' : '— (off)' });
    const difCell = el('span', { class: 'wtd-dif' },
      numBox(dif[0], (v) => setTask(type, (t) => { t.difficulty = [Math.max(0, v || 0), (t.difficulty || dif)[1]]; }), { min: 0, step: 0.5, path: `t.${type}.d0`, cls: 'tiny' }),
      el('span', { class: 'muted', text: '→' }),
      numBox(dif[1], (v) => setTask(type, (t) => { t.difficulty = [(t.difficulty || dif)[0], Math.max(0, v || 0)]; }), { min: 0, step: 0.5, path: `t.${type}.d1`, cls: 'tiny' }),
      skulls(Number(dif[1]) || 0, 'wtd-mini-sk'));
    const head = el('div', { class: 'wtd-trow' + (on ? '' : ' off') },
      cb,
      el('span', { class: 'wtd-tname' }, el('b', { text: info.label }), el('code', { text: type })),
      el('span', { class: 'wtd-wcell' }, slider, wnum),
      chanceCell, difCell,
      el('button', { class: 'btn small ghost', type: 'button', text: open ? '▾' : '▸', title: 'its numbers, words and extras', onclick: () => { S.open[type] = !open; redraw(); } }));
    const box = el('div', { class: 'wtd-task' + (open ? ' open' : '') }, head);
    if (open) box.appendChild(taskDetail(type, tc, ctx));
    return box;
  }

  function taskDetail(type, tc, ctx) {
    const info = M.TYPE_INFO[type];
    const T = M.TYPES[type];
    const body = el('div', { class: 'wtd-tbody' });
    body.appendChild(el('p', { class: 'muted small', text: info.help }));
    if (T.param) {
      const ns = Array.isArray(tc.n) ? tc.n : [];
      const g = el('div', { class: 'wtd-ranges' });
      g.appendChild(el('span', { class: 'muted small', text: T.down ? 'number (lower is harder)' : 'number' }));
      for (const i of [0, 1, 2]) {
        const e = ns[i] || ns[ns.length - 1] || [0, 0];
        const setN = (j) => (v) => setTask(type, (t) => {
          const arr = (Array.isArray(t.n) ? t.n : []).map((x) => (Array.isArray(x) ? x.slice() : [0, 0]));
          while (arr.length < 3) arr.push((arr[arr.length - 1] || [0, 0]).slice());
          arr[i][j] = Math.max(0, v || 0);
          t.n = arr;
        });
        const r = M.scaledRange(cfg(), type, tc, i, S.sim.P);
        g.appendChild(el('span', { class: 'wtd-range' }, el('small', { text: `Stage ${i + 1}` }),
          numBox(e[0], setN(0), { min: 0, path: `t.${type}.n.${i}.0`, cls: 'tiny', title: 'the easy end' }), el('span', { class: 'muted', text: 'to' }),
          numBox(e[1], setN(1), { min: 0, path: `t.${type}.n.${i}.1`, cls: 'tiny', title: 'the hard end' }),
          el('small', { class: 'muted', text: S.sim.P ? `→ ${Math.round(r[0])}–${Math.round(r[1])} at ${S.sim.P} beaten` : '' })));
      }
      body.appendChild(g);
      body.appendChild(row('Step', 'the number is rounded to this', numBox(tc.step, (v) => setTask(type, (t) => { t.step = Math.max(1, Math.round(v || 1)); }), { min: 1, step: 1, path: `t.${type}.step` })));
      if (type === 'hp_floor') body.appendChild(row('Max', 'never past this (percent)', numBox(tc.max, (v) => setTask(type, (t) => { if (v == null) delete t.max; else t.max = Math.max(1, v); }), { min: 1, max: 100, path: `t.${type}.max` })));
      body.appendChild(row('Own growth', 'this type\'s growth per stage beaten instead of the board\'s (empty = the board\'s)', numBox(tc.growth, (v) => setTask(type, (t) => { if (v == null) delete t.growth; else t.growth = Math.max(0, v); }), { min: 0, step: 0.05, path: `t.${type}.growth` })));
    }
    if (type === 'kill_enemy') {
      body.appendChild(row('Min seconds', 'a creature must be on this stage\'s roster at least this long to be a target', numBox(tc.min_seconds, (v) => setTask(type, (t) => { t.min_seconds = Math.max(0, v || 0); }), { min: 0, step: 5, path: `t.${type}.min_seconds` })));
      body.appendChild(row('Cap a minute', 'never ask for more than this many a minute it is on the roster', numBox(tc.per_minute_cap, (v) => setTask(type, (t) => { t.per_minute_cap = Math.max(1, v || 1); }), { min: 1, step: 1, path: `t.${type}.per_minute_cap` })));
      const on = (ctx.creatures || []).filter((x) => !x.elite);
      if (on.length) body.appendChild(el('p', { class: 'muted small', text: `On Stage ${ctx.stage + 1}: ` + on.map((x) => `${x.name} ${Math.round(x.seconds)} s`).join(' · ') }));
    }
    if (type === 'kill_weapon' || type === 'max_weapon' || type === 'evolve_item' || type === 'damage_weapon' || type === 'item_level') {
      body.appendChild(row('Start weight', type === 'evolve_item' ? 'how likely his own weapon is against one card' : (type === 'item_level' ? 'how many times likelier his own weapon is than another item' : 'how many times likelier his own weapon is than another one'), numBox(tc.start_weight, (v) => setTask(type, (t) => { t.start_weight = Math.max(0, v || 0); }), { min: 0, step: 0.5, path: `t.${type}.start_weight` })));
      if (type !== 'evolve_item' && type !== 'item_level') body.appendChild(row('Other bonus', 'difficulty added when the weapon is not his own (he has to find it first)', numBox(tc.other_bonus, (v) => setTask(type, (t) => { t.other_bonus = Math.max(0, v || 0); }), { min: 0, step: 0.5, path: `t.${type}.other_bonus` })));
    }
    // pass 113 (lane TASKS): the new types' own settings
    if (type === 'item_level') {
      body.appendChild(row('Min level', 'the lowest level a poster asks for (2: "get it to level 2"); the highest is each item\'s own top level', numBox(tc.min_level, (v) => setTask(type, (t) => { t.min_level = Math.max(1, Math.round(v || 2)); }), { min: 1, step: 1, path: `t.${type}.min_level` })));
      const items = M.targetsOf(cfg(), type, ctx);
      if (items.length) body.appendChild(el('p', { class: 'muted small', text: `Stage ${ctx.stage + 1}: ` + items.map((x) => `${x.name} 2–${x.max_level}`).join(' · ') }));
    }
    if (type === 'barrels') body.appendChild(row('Max', 'never more barrels than this (35 stand at the start, broken ones come back now and then)', numBox(tc.max, (v) => setTask(type, (t) => { if (v == null) delete t.max; else t.max = Math.max(1, Math.round(v)); }), { min: 1, step: 1, path: `t.${type}.max` })));
    if (type === 'totems') body.appendChild(el('p', { class: 'muted small', text: `This map stands ${ctx.totem_poles || 0} Totem Poles at the least: never more gifts are asked.${(typeof TaskPics !== 'undefined' && TaskPics.S.sources) ? '' : ' (the structures are not read yet: restart the editor if this stays 0)'}` }));
    if (M.TARGET_FIRST.includes(type)) body.appendChild(targetMults(type, tc, ctx));
    if (type === 'kill_elites') body.appendChild(el('p', { class: 'muted small', text: `Stage ${ctx.stage + 1} brings about ${ctx.elite_estimate} Elite${ctx.elite_estimate === 1 ? '' : 's'} (its Elite events and Elite rows): never more are asked.` }));
    const txt = (key, label, help) => {
      const inp = el('input', { type: 'text', class: 'txt wide', value: tc[key] || '', 'data-path': `t.${type}.${key}` });
      inp.addEventListener('change', () => setTask(type, (t) => { t[key] = inp.value; }));
      return row(label, help, inp);
    };
    body.appendChild(txt('name', 'Name', 'the big name on the poster: {target} {hero} {stage} {boss}'));
    body.appendChild(txt('text', 'Task line', 'what to do: {n} {target} {hero} {stage} {boss} {time}'));
    return body;
  }

  /** Pass 113 (lane TASKS): a factor per target on the type's range (`target_mult`): every target this stage can name,
   *  with its range at the factor; empty = 1. */
  function targetMults(type, tc, ctx) {
    const tm = (tc.target_mult && typeof tc.target_mult === 'object') ? tc.target_mult : {};
    const cands = M.targetsOf(Object.assign({}, cfg(), { items_seen_only: false, creatures_met_only: false }), type, ctx);
    const box = el('div', { class: 'wtd-ranges' });
    box.appendChild(el('span', { class: 'muted small', text: 'own factor (× the range; empty = 1)' }));
    const ids = cands.map((x) => String(x.id)).concat(Object.keys(tm).filter((id) => !cands.some((x) => String(x.id) === id)));
    if (!ids.length) box.appendChild(el('span', { class: 'muted small', text: 'nothing this stage can name' }));
    for (const id of ids) {
      const x = cands.find((c) => String(c.id) === id) || { id, name: id };
      const r = M.targetRange(tc, M.scaledRange(cfg(), type, tc, ctx.stage, S.sim.P), id);
      box.appendChild(el('span', { class: 'wtd-range' }, el('small', { text: x.name || id }),
        numBox(tm[id], (v) => setTask(type, (t) => { const m = Object.assign({}, t.target_mult || {}); if (v == null) delete m[id]; else m[id] = Math.max(0, v); if (Object.keys(m).length) t.target_mult = m; else delete t.target_mult; }), { min: 0, step: 0.05, path: `t.${type}.target_mult.${id}`, cls: 'tiny', title: `${id}: 1 when empty` }),
        el('small', { class: 'muted', text: `→ ${Math.round(r[0]).toLocaleString('en-US')}–${Math.round(r[1]).toLocaleString('en-US')}` })));
    }
    return box;
  }

  // ------------------------------------------------------------------ "Try the board"

  function simPane(ctx) {
    const sim = S.sim;
    const pane = el('aside', { class: 'wtd-sim' });
    pane.appendChild(el('div', { class: 'wtd-sim-head' }, el('h3', { text: 'Try the posters' }), el('span', { class: 'muted small', text: 'as they float in after the descent, with the config as it is on this page, saved or not' })));
    const stages = typeof App !== 'undefined' && App.stageList ? App.stageList() : [];
    const stSel = el('select', { 'data-path': 'sim.stage' });
    stages.forEach((s, i) => stSel.appendChild(el('option', { value: i, text: `Stage ${i + 1} · ${s.name}`, selected: i === sim.stage })));
    stSel.addEventListener('change', () => { sim.stage = Number(stSel.value); roll(); });
    const hSel = el('select', { 'data-path': 'sim.hero' });
    for (const h of playable()) hSel.appendChild(el('option', { value: h.id, text: h.name, selected: h.id === sim.hero }));
    hSel.addEventListener('change', () => { sim.hero = hSel.value; roll(); });
    const pIn = el('input', { type: 'range', min: 0, max: Math.max(stages.length, 1), step: 1, value: sim.P, class: 'wtd-p', 'data-path': 'sim.P' });
    const pOut = el('b', { text: String(sim.P) });
    pIn.addEventListener('input', () => { pOut.textContent = pIn.value; });
    pIn.addEventListener('change', () => { sim.P = Number(pIn.value); roll(); });
    const tog = (key, label) => { const cb = el('input', { type: 'checkbox', checked: !!sim[key] }); cb.addEventListener('change', () => { sim[key] = cb.checked; roll(); }); return el('label', { class: 'cb' }, cb, el('span', { text: label })); };
    pane.appendChild(el('div', { class: 'wtd-sim-ctl' },
      el('label', { class: 'wtd-l' }, el('span', { text: 'Stage' }), stSel),
      el('label', { class: 'wtd-l' }, el('span', { text: 'Hero' }), hSel),
      el('label', { class: 'wtd-l wtd-prog' }, el('span', {}, 'Stages beaten ', pOut), pIn),
      el('div', { class: 'wtd-togs' }, tog('metAll', 'met every creature'), tog('seenAll', 'seen every item'), tog('unlocks', 'every unlock done'))));
    pane.appendChild(el('div', { class: 'wtd-roll-row' },
      el('button', { class: 'btn primary wtd-roll', type: 'button', text: '🎲  Roll the posters', onclick: () => roll() }),
      el('span', { class: 'muted small', text: sim.posters.length ? `roll #${sim.seed}` : '' })));
    const board = el('div', { class: 'wtd-board' });
    if (!sim.posters.length) board.appendChild(el('p', { class: 'muted', text: 'Nothing can be posted here with these settings (no type has a target). Tick "met every creature" or turn a type on.' }));
    sim.posters.forEach((c, i) => board.appendChild(poster(c, i)));
    pane.appendChild(board);
    const pc = sim.posters[sim.picked];
    pane.appendChild(el('div', { class: 'wtd-pick' }, pc
      ? [el('b', { text: `${pc.name.toUpperCase()} · ` }), el('span', { text: `${pc.text}. ` }), el('span', { text: `Difficulty ${pc.d} (${pc.skulls} skull${pc.skulls === 1 ? '' : 's'}) · pays ` }), el('b', { class: 'wtd-gold', text: pc.reward.toLocaleString('en-US') }), el('span', { class: 'muted', text: ` · ${pc.type}${pc.target ? ' → ' + pc.target : ''}` })]
      : el('span', { class: 'muted', text: 'Click a poster to pick it, as the player taps one.' })));
    return pane;
  }

  // the torn outline (as WPoster: a straight top, ragged sides, a torn foot) as a CSS polygon in percent
  function tornClip(seed) {
    const r = M.mulberry32(seed);
    const pts = [];
    const sx = 14, sy = 22, t = 1.6;
    for (let i = 0; i <= sx; i++) pts.push([i / sx * 100, r() * t * 0.4]);
    for (let i = 1; i <= sy; i++) pts.push([100 - r() * t * 0.8, i / sy * 100]);
    for (let i = sx * 2; i >= 0; i--) pts.push([i / (sx * 2) * 100, 100 - r() * t * 1.4 - (i % 2 === 0 ? t * 0.6 : 0)]);
    for (let i = sy - 1; i > 0; i--) pts.push([r() * t * 0.8, i / sy * 100]);
    return 'polygon(' + pts.map(([x, y]) => `${x.toFixed(2)}% ${y.toFixed(2)}%`).join(', ') + ')';
  }

  function hashOf(s) { let h = 2166136261; for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); } return h >>> 0; }

  /** The picture of a poster's still, as the game's WPoster.still_texture picks it. */
  function stillNode(still) {
    const s = still || {};
    const box = el('div', { class: 'wp-still' });
    const enemies = (typeof App !== 'undefined' && App.S.enemies) || [];
    if (s.kind === 'enemy' || s.kind === 'boss') {
      const c = enemies.find((x) => x.id === s.id);
      if (c) {
        const look = (c.looks || []).find((l) => l.code === c.play) || (c.looks || []).find((l) => l.base) || { anims: c.anims, strip_cols: c.strip_cols };
        const total = Object.values(look.anims || c.anims || {}).reduce((a, n) => a + Number(n || 0), 0) || 1;
        const cols = Number(look.strip_cols || 0) > 0 ? Number(look.strip_cols) : total;
        const rows = Math.ceil(total / cols);
        box.classList.add('cell');
        box.style.backgroundImage = `url("${c.sprite_play || c.sprite}")`;
        box.style.backgroundSize = `${cols * 100}% ${rows * 100}%`;
        box.style.backgroundPosition = '0 0';
        box.title = `${c.name}: the first frame of ${c.play || 'its'} strip`;
      }
    } else if (s.kind === 'weapon') {
      const w = ((S.items && S.items.weapons) || []).find((x) => x.id === s.id);
      if (w) box.style.backgroundImage = `url("${w.icon_play || w.icon}")`;
    } else if (s.kind === 'card') {
      const p = ((S.items && S.items.lines) || []).find((x) => x.id === s.id);
      if (p) box.style.backgroundImage = `url("${p.icon_play || p.icon}")`;
    } else if (s.kind === 'hero') {
      const h = (S.heroes || []).find((x) => x.id === s.id);
      if (h) { box.classList.add(h.title_play ? 'cutout' : 'icon'); box.style.backgroundImage = `url("${h.title_play || h.icon_play}")`; }
    } else if (s.kind === 'stage') {
      box.classList.add('cover');
      box.style.backgroundImage = `url("${ART}stages/${s.id}_s${Number(s.stage || 0) + 1}.jpg")`;
    } else if (s.kind === 'passive' || s.kind === 'pickup' || s.kind === 'structure' || (s.kind === 'art' && s.id !== 'chest' && s.id !== 'coin')) {
      // pass 113 (lane TASKS): a passive item's icon, the Heart's, a structure's (the Totem Pole, the Healing Well), the
      // barrel, the fire, the poison flask (tasks.js knows their addresses)
      const url = typeof TaskPics !== 'undefined' ? TaskPics.urlOf(s) : '';
      if (url) box.style.backgroundImage = `url("${url}")`;
    } else if (s.kind === 'art') {
      box.style.backgroundImage = `url("${ART}wanted/${s.id === 'chest' ? 'chest_closed' : 'coin'}.png")`;
    } else if (s.kind === 'badge') {
      box.style.backgroundImage = `url("${ART}badges/${s.id}.png")`;
    }
    return box;
  }

  function poster(c, i) {
    const tilt = [-2.5, 1.5, 3][i % 3];
    const picked = S.sim.picked === i;
    const wrap = el('div', { class: 'wp-wrap' + (picked ? ' picked' : ''), style: `--tilt:${picked ? 0 : tilt}deg`, title: 'click to pick it' });
    wrap.addEventListener('click', () => { S.sim.picked = i; redraw(); });
    const p = el('div', { class: 'wp', style: `clip-path:${tornClip(hashOf(c.type + c.target + c.n))}` });
    p.appendChild(el('div', { class: 'wp-frame' }));
    p.appendChild(el('div', { class: 'wp-head', text: 'WANTED' }));
    p.appendChild(el('div', { class: 'wp-rule' }));
    const pic = el('div', { class: 'wp-pic' + ((c.still || {}).kind === 'stage' ? ' stage' : '') }, stillNode(c.still));
    if ((c.still || {}).badge && (c.still || {}).kind !== 'badge') pic.appendChild(el('img', { class: 'wp-badge', src: `${ART}badges/${c.still.badge}.png`, alt: '' }));
    p.appendChild(pic);
    p.appendChild(el('div', { class: 'wp-name' + (c.name.length > 14 ? ' long' : ''), text: c.name.toUpperCase() }));
    p.appendChild(el('div', { class: 'wp-task', text: c.text }));
    p.appendChild(el('div', { class: 'wp-gap' }));
    p.appendChild(el('div', { class: 'wp-rl', text: 'REWARD' }));
    p.appendChild(el('div', { class: 'wp-reward' }, el('img', { src: `${ART}wanted/coin.png`, alt: '' }), el('span', { text: c.reward.toLocaleString('en-US') })));
    p.appendChild(skulls(c.d, 'wp-skulls'));
    wrap.appendChild(p);
    wrap.appendChild(el('div', { class: 'wp-nail' }));
    return wrap;
  }

  return { render, save, dirty, load, roll, S };
})();
