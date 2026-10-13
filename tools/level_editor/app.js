// The Level Editor's hub (pass 53, pass 54): the map in memory, undo history, validation, the time maths every lane
// shares (model.js holds the formulas), selection, Save / Revert / Export and the keyboard. The tabs (timeline.js,
// inspector.js, settings.js, creatures.js, instructions.js) read App.S and call back into App. Pass 58: a row's numbers
// from its start (creatureAt's t0, rowNumbers), the Actual lanes' series, the estimate refreshed during a drag, and the
// size and colour ranges checked before a save. Pass 66: the asset tabs (Enemies' editor, Heroes, Items, Jobs) keep their
// own documents in assets.js; Save / Undo / Redo / Revert, the top bar and beforeunload ask Assets.owns(S.tab) and
// Assets.hasDoc(S.tab) first and act on the open document, else on the map as before.
'use strict';

const App = (() => {
  const { el, fmtT, clone } = U;
  const M = Model;
  const BOSS_WINDOW = 30;   // seconds after a boss event in which another event fires only once the fight is over
  const HISTORY_MAX = 300;
  // one colour per creature on the Roster and Share lanes (pass 54), in the order the creatures first appear
  const CREATURE_COLORS = ['#3987e5', '#d95926', '#199e70', '#c98500', '#d55181', '#9085e9', '#4cb5c3', '#e66767', '#8bbf3f', '#b07a3a', '#e0b341', '#7a8cff', '#c46fd6', '#5fbf9f', '#b8b8b0', '#ff8f70'];

  const S = {
    maps: [], mapId: '', map: null, tl: null,
    saved: '',                  // JSON of the map as loaded (in the pass-54 shape) / last saved: the dirty check
    history: [], future: [],
    sel: null,                  // {kind: 'roster'|'wave'|'event'|'cap'|'hp'|'dmg'|'share'|'specials'|'paths'|'pickups', i}
    tab: 'timeline',
    enemies: [], byId: {}, elites: [], pickups: [], schema: '',
    issues: { errors: [], warnings: [], marks: {} },
    saving: false,
    level: 1,                   // the hero level the hover cards and the readout assume (pass 54)
    enemiesRev: 0,              // bumped whenever the creature list is read again (the estimate's cache key)
    fit: null,                  // pass 57: the server's kill rate, boss fight and portal wait from the run records
    assume: { turnover: null, bossSeconds: null, portalSeconds: null },  // pass 57: the page's own numbers (null = the fit)
  };

  // ------------------------------------------------------------------ loading

  async function getJSON(url) {
    const r = await fetch(url, { cache: 'no-store' });
    if (!r.ok) throw new Error(`${url}: HTTP ${r.status}`);
    return r.json();
  }

  function setEnemies(list) {
    S.enemies = list;
    S.enemiesRev++;
    S.byId = {};
    for (const c of list) S.byId[c.id] = c;
  }

  async function init() {
    try {
      const [maps, enemies, elites, pickups] = await Promise.all([getJSON('/api/maps'), getJSON('/api/enemies'), getJSON('/api/elites'), getJSON('/api/pickups')]);
      S.maps = maps; S.elites = elites; S.pickups = pickups;
      setEnemies(enemies);
      fetch('/api/schema', { cache: 'no-store' }).then((r) => r.text()).then((t) => { S.schema = t; if (S.tab === 'instructions') render('tab'); }).catch(() => {});
    } catch (e) {
      status('The server did not answer: ' + e.message, 'bad');
      return;
    }
    const sel = document.getElementById('map-select');
    U.clear(sel);
    for (const m of S.maps) sel.appendChild(el('option', { value: m.id, text: `${m.name} (${m.id})` }));
    sel.addEventListener('change', () => loadMap(sel.value));
    wireTopBar();
    wireTabs();
    wireKeys();
    Timeline.mount(document.getElementById('timeline'));
    const want = new URLSearchParams(location.search).get('map');
    const first = S.maps.find((m) => m.id === want) || S.maps[0];
    if (first) await loadMap(first.id); else status('No maps under game/content/maps', 'bad');
  }

  /** The creature list again (after the Creatures tab set a default look: the in-play icons change). */
  async function refreshCreatures() {
    setEnemies(await getJSON('/api/enemies'));
    render('all');
  }

  async function loadMap(id) {
    if (dirty() && !confirm('Unsaved changes will be lost. Load anyway?')) {
      document.getElementById('map-select').value = S.mapId; return;
    }
    try {
      const map = await getJSON('/api/map/' + id);
      if (!map.timeline_data) map.timeline_data = {};
      // pass 54: the roster in the new shape in memory (presence keyframes, row ids); Save writes it so
      const conv = M.normaliseRoster(map.timeline_data);
      S.mapId = id; S.map = map; S.tl = map.timeline_data;
      S.saved = JSON.stringify(map);
      S.history = []; S.future = []; S.sel = null;
      document.getElementById('map-select').value = id;
      document.getElementById('map-name').textContent = map.name || id;
      document.title = `${map.name || id} · 88fits Level Editor`;
      const m = S.maps.find((x) => x.id === id);
      document.getElementById('map-file').textContent = m ? m.file : '';
      const note = conv.converted || conv.ided ? ` · ${conv.converted ? `${conv.converted} roster rows read from weight / weight_late as presence keyframes` : ''}${conv.converted && conv.ided ? ', ' : ''}${conv.ided ? `${conv.ided} rows given an id` : ''} (the next Save writes the new shape)` : '';
      status(`Loaded ${m ? m.file : id}${note}`);
      loadAssume(id);
      S.fit = null;
      fetchFit(id);
      render('all');
      if (Timeline.fit) Timeline.fit();
    } catch (e) {
      status('Could not load the map: ' + e.message, 'bad');
    }
  }

  // ------------------------------------------------------------------ creatures

  const creature = (id) => S.byId[id] || null;
  const creatureName = (id) => (S.byId[id] ? S.byId[id].name : (id || '(none)'));
  const elite = (id) => S.elites.find((e) => e.id === id) || null;
  const pickup = (id) => S.pickups.find((p) => p.id === id) || null;

  /** Whether `code` is an art variant of the creature (empty = the one in play). */
  function variantOk(id, code) {
    if (!code) return true;
    const c = creature(id);
    if (!c) return false;
    return c.variants.some((v) => v.code === code) || code === c.variant || code === c.variant_base;
  }

  /** The icon a row / alternative / event shows: its art variant's when it names one, else the look in play (pass 54:
   *  the game shows the in-play variant's icon, the top-level one differed for nine creatures). */
  function iconFor(id, variant) {
    const c = creature(id);
    if (!c) return '';
    if (variant) {
      const v = c.variants.find((x) => x.code === variant);
      if (v) return v.icon;
    }
    return c.icon_play || c.icon;
  }

  /** The code a row plays: its own `variant`, else the creature's look in play. */
  function playCode(id, variant) {
    const c = creature(id);
    return variant || (c ? c.play || c.variant || '' : '');
  }

  let colorKey = '', colorMap = {};
  /** One colour per creature (the Roster areas, the Share band and its legend), by the order the creatures first
   *  appear on the roster's clock. */
  function creatureColor(id) {
    const rows = tl().roster || [];
    const key = rows.map((r) => `${r.enemy}@${r.t}`).join('|');
    if (key !== colorKey) {
      colorKey = key; colorMap = {};
      const order = rows.map((r, i) => ({ id: r.enemy, t: Number(r.t) || 0, i })).sort((a, b) => a.t - b.t || a.i - b.i);
      let n = 0;
      for (const o of order) if (!(o.id in colorMap)) colorMap[o.id] = CREATURE_COLORS[n++ % CREATURE_COLORS.length];
    }
    if (!(id in colorMap)) {
      let h = 0;
      for (const ch of String(id)) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
      colorMap[id] = CREATURE_COLORS[h % CREATURE_COLORS.length];
    }
    return colorMap[id];
  }

  // ------------------------------------------------------------------ time maths (what the director does with the numbers)

  const tl = () => S.tl || {};
  const stageLength = () => M.stageLength(tl());
  const stages = () => M.stages(tl());
  const runEnd = () => M.runEnd(tl());
  /** The axis runs a little into endless, so open rows and timers show where they go on. */
  const viewEnd = () => runEnd() + Math.max(120, Math.round(stageLength() * 0.35));
  /** 0-based stage index at run second t (stages() and above = endless). */
  const stageAt = (t) => M.stageAt(tl(), t);
  const stageName = (s) => (s >= stages() ? 'endless' : `stage ${s + 1}`);
  const stageMult = (s, t) => M.stageMult(tl(), s, t);
  const samplePoints = (pts, t) => M.samplePoints(pts, t);

  function curveAt(t) {
    const cc = tl().cap_curve || [];
    if (!cc.length) return (Number(tl().cap_start) || 0) + (Number(tl().cap_per_minute) || 0) * t / 60;
    return M.samplePoints(cc.slice().sort((a, b) => a[0] - b[0]), t);
  }

  /** The live cap at t (the timeline's cap_at: the curve, plus cap_per_stage per stage, under cap_max). */
  function capAt(t) {
    const s = stageAt(t);
    const base = curveAt(t) + (Number(tl().cap_per_stage) || 0) * s;
    const mx = tl().cap_max == null ? Infinity : Number(tl().cap_max);
    return Math.max(0, Math.min(Math.floor(base), mx));
  }

  function hellCapAt(t) {
    const hc = tl().hell_cap || [];
    if (!hc.length) return 0;
    const s = Math.min(stageAt(t), hc.length - 1);
    return Number(hc[s]) * capAt(t);
  }

  /** The HP × lane's value at t: the hp_curve, else the legacy hp_growth / hp_power formula. */
  const hpTimeMult = (t) => M.hpTimeMult(tl(), t);
  /** The ATK × lane's value at t: the damage_curve, else 1. */
  const dmgTimeMult = (t) => M.dmgTimeMult(tl(), t);
  const levelHp = () => 1 + (Number(tl().level_hp_per_level) || 0) * Math.max(S.level - 1, 0);
  const levelDmg = () => 1 + (Number(tl().level_damage_per_level) || 0) * Math.max(S.level - 1, 0);

  /** HP multiplier at t for an ordinary creature: the HP curve × stage × the assumed hero level × creature_hp_mult. */
  function hpMultAt(t) {
    const time = hpTimeMult(t), stage = stageMult(stageAt(t), t), level = levelHp();
    const chm = tl().creature_hp_mult == null ? 1 : Number(tl().creature_hp_mult);
    return { time, stage, level, creature: chm, total: time * stage * level * chm };
  }

  /** Damage multiplier at t: the damage curve × stage × the assumed hero level × creature_damage_mult. */
  function dmgMultAt(t) {
    const time = dmgTimeMult(t), stage = stageMult(stageAt(t), t), level = levelDmg();
    const cdm = tl().creature_damage_mult == null ? 1 : Number(tl().creature_damage_mult);
    return { time, stage, level, creature: cdm, total: time * stage * level * cdm };
  }

  /** One creature's HP and ATK at t with a row's overrides, at the assumed hero level (model.js creatureAt); pass 58:
   *  `t0` is the row's start (its numbers fixed from there, R1), missing = t. */
  function creatureAt(c, stats, t, t0, given) { return M.creatureAt(tl(), c, stats, t, S.level, t0, given); }
  /** An event's numbers at second t (the fix round of lane WV: a row or wave bringing the same creature in the same look
   *  then lends it its numbers; model.js eventNumbers). */
  function eventNumbers(id, variant, stats, t) { return M.eventNumbers(tl(), S.byId, id, variant, stats, t, lateT()); }
  /** "row r12", or "wave Test wave (alternative 2, 33% of runs)": the source an event joins (openSourceOf's result). */
  function sourceName(j) {
    if (!j) return '';
    if (j.kind === 'roster') { const r = (tl().roster || [])[j.i] || {}; return `row ${r.id || j.i + 1}`; }
    const w = (tl().waves || [])[j.i] || {};
    const many = Array.isArray(w.alts) && w.alts.length > 1;
    return `wave ${w.name || w.id || j.i + 1}${many ? ` (alternative ${j.k + 1}, ${Math.round(j.share * 100)}% of runs)` : ''}`;
  }
  /** A row's own HP and ATK, fixed from its start t0 (pass 58, R1: model.js rowNumbers). */
  function rowNumbers(c, stats, t0) { return M.rowNumbers(tl(), c, stats, t0); }
  /** The bite's knockback in m/s with a row's overrides (the creature's own, else the game's default). */
  function knockbackOf(c, stats) { return M.knockbackOf(c, stats).value; }

  const lateT = () => (tl().weight_late_t == null ? M.DEF.weight_late_t : Number(tl().weight_late_t));
  function rowWeight(r, t) { return M.rowWeight(r, t, lateT()); }

  /** The roster rows open at t with their weights, normalised within their channel. */
  function rosterAt(t) {
    const rows = tl().roster || [];
    const open = [];
    rows.forEach((r, i) => {
      const start = Number(r.t) || 0, until = r.until == null || r.until === '' ? Infinity : Number(r.until);
      if (t >= start && t < until) open.push({ row: r, i, w: rowWeight(r, t), hell: r.channel === 'hell' });
    });
    for (const ch of [false, true]) {
      const part = open.filter((o) => o.hell === ch);
      const total = part.reduce((a, o) => a + o.w, 0) || 1;
      for (const o of part) o.norm = o.w / total;
    }
    return open;
  }

  /** Where a wave's block ends: `until`, else t + every × ceil(count / burst), else (count 0, no until) never. */
  function waveEnd(w) {
    const t = Number(w.t) || 0;
    if (w.until != null && w.until !== '') return Number(w.until);
    const count = Number(w.count) || 0, burst = Math.max(1, Number(w.burst) || 1), every = Number(w.every) || 0;
    if (count > 0) return t + every * Math.ceil(count / burst);
    return Infinity;
  }

  function wavesAt(t) {
    return (tl().waves || []).map((w, i) => ({ w, i })).filter(({ w }) => t >= (Number(w.t) || 0) && t < waveEnd(w));
  }

  function nextEvent(t) {
    let best = null;
    (tl().events || []).forEach((ev, i) => {
      const et = Number(ev.t) || 0;
      if (et >= t && (!best || et < best.t)) best = { ev, i, t: et };
    });
    return best;
  }

  function eventLabel(ev) {
    if (ev.name) return ev.name;
    const ids = U.idList(ev.enemy);
    const type = FIELDS.EVENT_TYPES[ev.type] ? FIELDS.EVENT_TYPES[ev.type].label : ev.type;
    if (ev.type === 'elite_every') {
      const iv = Array.isArray(ev.interval) ? `${ev.interval[0]}–${ev.interval[ev.interval.length - 1]}` : (ev.interval == null ? 90 : ev.interval);
      return `${type} ${iv} s`;
    }
    if (ev.type === 'swarm') return `${type}: ${ev.count || 40} ${ids.length ? ids.map(creatureName).join(' / ') : 'walkers'}`;
    if (!ids.length) return type + (ev.type === 'elite' ? ' (random)' : '');
    if (ids.length === 1) return `${type}: ${creatureName(ids[0])}`;
    return `${type}: one of ${ids.length}`;
  }

  /** The chances of an event's creatures as fractions (equal when `weights` is missing). */
  function eventShares(ev) {
    const ids = U.idList(ev.enemy);
    const ws = Array.isArray(ev.weights) ? ev.weights.map(Number) : ids.map(() => 1);
    const total = ids.reduce((a, _, k) => a + (ws[k] == null ? 1 : ws[k]), 0) || 1;
    return ids.map((id, k) => ({ id, share: (ws[k] == null ? 1 : ws[k]) / total }));
  }

  /** Every alternative of a wave with its normalised chance (the wave's own creature when it has no alts). */
  function waveAlts(w) {
    const alts = Array.isArray(w.alts) && w.alts.length ? w.alts : [{ chance: 1, enemy: w.enemy, variant: w.variant, pack: w.pack, stats: w.stats, own: true }];
    const total = alts.reduce((a, x) => a + (x.chance == null ? 1 : Number(x.chance)), 0) || 1;
    return alts.map((a, k) => ({ alt: a, k, share: (a.chance == null ? 1 : Number(a.chance)) / total }));
  }

  // ------------------------------------------------------------------ the "Spawned so far" estimate (pass 57)

  /** The kill rate, the boss fight and the portal wait the server fits from Garry's run records for this map
   *  (/api/turnover); the lane draws with the fallback until it answers. */
  async function fetchFit(id) {
    try {
      const f = await getJSON('/api/turnover/' + id);
      if (S.mapId !== id) return;
      S.fit = f;
      if (S.tab === 'timeline') render('timeline');
    } catch (_) { /* no fit: the lane keeps the fallback numbers */ }
  }

  const assumeKey = (id) => `88fits-editor-spawned-${id}`;
  /** The page's own assumptions for this map (a page setting like the hero level: never written to the map). */
  function loadAssume(id) {
    S.assume = { turnover: null, bossSeconds: null, portalSeconds: null };
    try {
      const a = JSON.parse(localStorage.getItem(assumeKey(id)) || 'null');
      if (U.isObj(a)) for (const k of Object.keys(S.assume)) if (typeof a[k] === 'number' && isFinite(a[k]) && a[k] >= 0) S.assume[k] = a[k];
    } catch (_) { /* no storage: the fit's numbers */ }
  }

  /** Set one assumption (null = back to the fit's number) and draw again. */
  function setAssume(key, value) {
    S.assume[key] = value == null || !isFinite(value) || value < 0 ? null : value;
    try { localStorage.setItem(assumeKey(S.mapId), JSON.stringify(S.assume)); } catch (_) { /* fine */ }
    render('timeline');
  }

  /** What the estimate plays with: the page's numbers where set, else the fit's (the kill rate minute by minute when the
   *  records allow, else per stage, else one number), else the model's fallback; the map's first skin and boss. */
  function spawnOpts() {
    const f = S.fit || {};
    const a = S.assume || {};
    let turnover;
    if (a.turnover != null) turnover = a.turnover;
    else if (Array.isArray(f.curve) && f.curve.length) turnover = f.curve;
    else if (Array.isArray(f.by_stage) && f.by_stage.length) turnover = f.by_stage;
    else turnover = f.turnover != null ? f.turnover : M.EST_DEF.turnover;
    const skins = S.map && U.isObj(S.map.skins) ? Object.values(S.map.skins) : [];
    return {
      turnover,
      bossSeconds: a.bossSeconds != null ? a.bossSeconds : (f.boss_seconds != null ? f.boss_seconds : M.EST_DEF.bossSeconds),
      portalSeconds: a.portalSeconds != null ? a.portalSeconds : (f.portal_seconds != null ? f.portal_seconds : M.EST_DEF.portalSeconds),
      skin: skins.length ? String(skins[0]) : '',
      boss: S.map && S.map.boss ? String(S.map.boss) : '',
      end: viewEnd(),
    };
  }

  /** Where the kill rate comes from, in words (the lane's label and its card). */
  function turnoverSource() {
    const f = S.fit;
    if (S.assume.turnover != null) return 'your number';
    if (!f || f.source !== 'records') return f ? 'the default (no runs on this map yet)' : 'the default (reading your runs…)';
    const n = (f.runs || []).length;
    return `your ${n} run${n === 1 ? '' : 's'}`;
  }

  let spawnCache = { key: '', est: null, ms: 0, at: 0 };
  /** While a drag runs the estimate is run again at most this often (pass 58: the Actual lanes follow a dragged row a few
   *  times a second; it was the last one until the drop). */
  const DRAG_ESTIMATE_MS = 350;
  /** The estimate for the map as it is (cached until the timeline, the assumptions or the creatures change). With
   *  `allowStale` (a drag in progress) the last one comes back unless it is older than DRAG_ESTIMATE_MS. */
  function spawned(allowStale) {
    const opts = spawnOpts();
    const key = JSON.stringify([S.mapId, S.enemiesRev, opts, S.tl]);
    if (key === spawnCache.key && spawnCache.est) return { est: spawnCache.est, stale: false, opts, ms: spawnCache.ms };
    if (allowStale && spawnCache.est && performance.now() - spawnCache.at < DRAG_ESTIMATE_MS) return { est: spawnCache.est, stale: true, opts, ms: spawnCache.ms };
    const t0 = performance.now();
    const est = M.spawnEstimate(tl(), S.enemies, opts);
    spawnCache = { key, est, ms: performance.now() - t0, at: performance.now() };
    return { est, stale: false, opts, ms: spawnCache.ms };
  }

  /** The Actual HP x / ATK x lanes (pass 58): Model.actualSeries every second over the view, from the estimate's
   *  per-source tallies and every row's multiples as the map stands now. `res` is spawned()'s result. */
  const ACTUAL_WINDOW = 10;
  function actual(res) {
    const r = res || spawned(false);
    return { series: M.actualSeries(tl(), S.byId, r.est, viewEnd(), 1, ACTUAL_WINDOW), est: r.est, stale: r.stale };
  }
  /** The Actual lanes at one second, with the rows behind the numbers (the hover card). */
  function actualAt(t, est) { return M.actualAt(tl(), S.byId, est || spawned(false).est, t, ACTUAL_WINDOW); }

  // ------------------------------------------------------------------ history

  const snapshot = () => JSON.stringify(S.map);

  /** Push `before` (a snapshot taken before a change) to the history when the map differs from it. */
  function pushHistory(before) {
    if (!S.map) return;
    const now = snapshot();
    if (now === before) return;
    S.history.push(before);
    if (S.history.length > HISTORY_MAX) S.history.shift();
    S.future = [];
  }

  /** Run `fn(tl, map)` as one undoable change and redraw (`what`: 'all' | 'timeline' | 'inspector' | 'none'). */
  function apply(fn, what) {
    const before = snapshot();
    fn(S.tl, S.map);
    pushHistory(before);
    render(what || 'all');
  }

  // pass 66: on an asset tab with an open document, Save / Undo / Redo / Revert and the top bar are that document's
  // (Assets.owns / Assets.hasDoc); with none open they stay the map's, as before
  function assetDoc() { return assetsTab() && Assets.hasDoc(S.tab); }

  function undo() {
    if (assetDoc()) { Assets.undo(S.tab); return; }
    if (!S.history.length) { status('Nothing to undo'); return; }
    S.future.push(snapshot());
    restore(S.history.pop());
    status('Undone');
  }

  function redo() {
    if (assetDoc()) { Assets.redo(S.tab); return; }
    if (!S.future.length) { status('Nothing to redo'); return; }
    S.history.push(snapshot());
    restore(S.future.pop());
    status('Redone');
  }

  function restore(json) {
    S.map = JSON.parse(json);
    if (!S.map.timeline_data) S.map.timeline_data = {};
    S.tl = S.map.timeline_data;
    if (S.sel && !selected()) S.sel = null;
    render('all');
  }

  const dirty = () => !!S.map && snapshot() !== S.saved;

  // ------------------------------------------------------------------ selection

  function selected() {
    const s = S.sel;
    if (!s) return null;
    if (s.kind === 'roster') return (tl().roster || [])[s.i] || null;
    if (s.kind === 'wave') return (tl().waves || [])[s.i] || null;
    if (s.kind === 'event') return (tl().events || [])[s.i] || null;
    return { kind: s.kind };
  }

  function select(sel, opts) {
    S.sel = sel;
    render('selection');
    if (sel && opts && opts.scroll && Timeline.scrollToSelection) Timeline.scrollToSelection();
  }

  const selKey = () => (S.sel ? (S.sel.i == null ? S.sel.kind : `${S.sel.kind}:${S.sel.i}`) : '');

  // ------------------------------------------------------------------ new items

  function firstCreatureId() {
    const rows = tl().roster || [];
    if (rows.length && creature(rows[0].enemy)) return rows[0].enemy;
    const c = S.enemies.find((x) => x.kind === 'enemy' && !x.retired && !x.hidden && x.archetype !== 'elite');
    return c ? c.id : (S.enemies[0] ? S.enemies[0].id : '');
  }

  function newWaveId() {
    const used = new Set((tl().waves || []).map((w) => w.id));
    let n = 1;
    while (used.has('w' + n)) n++;
    return 'w' + n;
  }

  function newWave(enemyId, t) {
    const id = enemyId || firstCreatureId();
    const at = Math.max(0, Math.round(t == null ? Timeline.viewCenter() : t));
    apply((d) => {
      if (!Array.isArray(d.waves)) d.waves = [];
      d.waves.push({ id: newWaveId(), name: `${creatureName(id)} wave`, t: at, count: 20, burst: 5, every: 2, pattern: 'pack', respect_cap: true, alts: [{ chance: 1, enemy: id }] });
      S.sel = { kind: 'wave', i: d.waves.length - 1 };
    });
    toast(`Added a wave at ${fmtT(at)}`);
  }

  /** A new row: presence 5 flat over two keyframes half a stage apart, so it can be shaped at once. */
  function newRow(enemyId, t) {
    const id = enemyId || firstCreatureId();
    const at = Math.max(0, Math.round(t == null ? Timeline.viewCenter() : t));
    apply((d) => {
      if (!Array.isArray(d.roster)) d.roster = [];
      d.roster.push({ id: M.newRowId(d), t: at, enemy: id, weights: [[at, 5], [at + Math.round(stageLength() / 2), 5]] });
      S.sel = { kind: 'roster', i: d.roster.length - 1 };
    });
    toast(`Added a roster row at ${fmtT(at)}`);
  }

  function newEvent(type, t) {
    const at = Math.max(0, Math.round(t == null ? Timeline.viewCenter() : t));
    apply((d) => {
      if (!Array.isArray(d.events)) d.events = [];
      const ev = { t: at, type };
      if (type === 'boss') { const b = S.enemies.find((c) => c.kind === 'boss'); if (b) ev.enemy = b.id; }
      if (type === 'elite_boss') { const e = S.enemies.filter((c) => c.archetype === 'elite' && !c.hidden).map((c) => c.id); if (e.length) ev.enemy = e; }
      if (type === 'swarm') { ev.enemy = firstCreatureId(); ev.count = 30; }
      if (type === 'elite_every') ev.interval = 120;
      d.events.push(ev);
      d.events.sort((a, b) => (Number(a.t) || 0) - (Number(b.t) || 0));
      S.sel = { kind: 'event', i: d.events.indexOf(ev) };
    });
    toast(`Added a ${FIELDS.EVENT_TYPES[type] ? FIELDS.EVENT_TYPES[type].label.toLowerCase() : type} event at ${fmtT(at)}`);
  }

  function deleteSelected() {
    const s = S.sel;
    if (!s || s.i == null) return;
    const list = s.kind === 'roster' ? 'roster' : s.kind === 'wave' ? 'waves' : s.kind === 'event' ? 'events' : null;
    if (!list || !tl()[list] || !tl()[list][s.i]) return;
    const item = tl()[list][s.i];
    const label = s.kind === 'roster' ? `row ${creatureName(item.enemy)}` : s.kind === 'wave' ? `wave ${item.name || item.id || ''}` : `event ${eventLabel(item)}`;
    apply((d) => { d[list].splice(s.i, 1); S.sel = null; });
    toast(`Deleted ${label}`, { undo: true });
  }

  function duplicateSelected() {
    const s = S.sel;
    if (!s || s.i == null) return;
    const list = s.kind === 'roster' ? 'roster' : s.kind === 'wave' ? 'waves' : s.kind === 'event' ? 'events' : null;
    if (!list || !tl()[list] || !tl()[list][s.i]) return;
    apply((d) => {
      const copy = clone(d[list][s.i]);
      if (list === 'waves') { copy.id = newWaveId(); copy.name = (copy.name || copy.id) + ' copy'; }
      if (list === 'roster') copy.id = M.newRowId(d);
      d[list].splice(s.i + 1, 0, copy);
      S.sel = { kind: s.kind, i: s.i + 1 };
    });
    toast('Duplicated');
  }

  /** Move a roster row from index `from` to `to` (pass 54: display order only; the game draws by weight, not order). */
  function moveRowTo(from, to) {
    const rows = tl().roster || [];
    if (from === to || from < 0 || from >= rows.length) return;
    const dest = Math.max(0, Math.min(rows.length - 1, to));
    if (dest === from) return;
    apply((d) => {
      const [r] = d.roster.splice(from, 1);
      d.roster.splice(dest, 0, r);
      S.sel = { kind: 'roster', i: dest };
    });
  }

  function moveRow(i, delta) { moveRowTo(i, i + delta); }

  /** Move the selection by `dt` seconds (both ends of a row or wave, and a row's presence keyframes with it). */
  function nudge(dt) {
    const s = S.sel;
    if (!s || s.i == null) return;
    apply((d) => {
      const list = s.kind === 'roster' ? d.roster : s.kind === 'wave' ? d.waves : s.kind === 'event' ? d.events : null;
      const it = list && list[s.i];
      if (!it) return;
      const t0 = Number(it.t) || 0;
      const nt = Math.max(0, t0 + dt);
      const moved = nt - t0;
      it.t = nt;
      if (it.until != null && it.until !== '') it.until = Math.max(nt + 1, Number(it.until) + moved);
      if (s.kind === 'roster') shiftWeights(it, moved);
    });
  }

  /** A row's presence keyframes moved with the row (they are run-clock times), never before 0. */
  function shiftWeights(r, dt) {
    if (!dt || !Array.isArray(r.weights)) return;
    for (const p of r.weights) if (Array.isArray(p)) p[0] = Math.max(0, Math.round((Number(p[0]) || 0) + dt));
  }

  const sortPoints = (pts) => { if (Array.isArray(pts)) pts.sort((a, b) => (Number(a[0]) || 0) - (Number(b[0]) || 0)); };

  // ------------------------------------------------------------------ validation

  const isPair = (p) => Array.isArray(p) && p.length >= 2 && !isNaN(Number(p[0])) && !isNaN(Number(p[1])) && p[0] !== null && p[1] !== null;
  const inOrder = (pts) => { for (let k = 1; k < pts.length; k++) if (Number(pts[k][0]) < Number(pts[k - 1][0])) return false; return true; };

  function validateCurve(key, c, mark, what) {
    if (c == null) return;
    if (!U.isObj(c)) { mark(key, 'error', `${what} must be a block {mode, points, formula}`); return; }
    if (c.mode != null && c.mode !== 'points' && c.mode !== 'formula') mark(key, 'error', `${what}: mode "${c.mode}" is neither points nor formula (the game reads ×1)`);
    const pts = c.points;
    if (pts != null && (!Array.isArray(pts) || pts.some((p) => !isPair(p)))) mark(key, 'error', `${what}: a point is not [seconds, multiplier]`);
    else if (Array.isArray(pts)) {
      if (!inOrder(pts)) mark(key, 'warn', `${what}: the points are not in time order (Save sorts them)`);
      if (pts.some((p) => Number(p[1]) < 0)) mark(key, 'error', `${what}: a negative multiplier`);
      if (M.curveMode(c) === 'points' && !pts.length) mark(key, 'warn', `${what}: manual points but none set: ×1 all run`);
    }
    if (c.formula != null) {
      if (!U.isObj(c.formula)) mark(key, 'error', `${what}: formula must be {kind, a, b}`);
      else if (c.formula.kind != null && !['linear', 'power', 'exponential'].includes(c.formula.kind)) mark(key, 'error', `${what}: unknown formula kind "${c.formula.kind}" (the game reads ×1)`);
    }
  }

  /** A stats block's size and colour ranges (pass 58, R2 / R3; Garry's "0 < min <= max"): errors block Save. */
  function statsIssues(st, key, mark, prefix) {
    if (!U.isObj(st)) return;
    for (const m of M.sizeIssues(st.size)) mark(key, 'error', `${prefix}${m}`);
    for (const m of M.tintIssues(st.tint)) mark(key, 'error', `${prefix}${m}`);
  }

  function validate() {
    const errors = [], warnings = [], marks = {};
    const d = tl();
    const mark = (key, level, msg) => {
      (level === 'error' ? errors : warnings).push({ key, msg });
      const m = marks[key] || (marks[key] = { level: 'warn', msgs: [] });
      if (level === 'error') m.level = 'error';
      m.msgs.push(msg);
    };
    const hard = Number(d.hard_cap) || Infinity;
    const SL = stageLength();
    const ids = new Map();
    (d.roster || []).forEach((r, i) => {
      const key = `roster:${i}`;
      if (!creature(r.enemy)) mark(key, 'error', `unknown creature "${r.enemy || ''}"`);
      else if (!variantOk(r.enemy, r.variant)) mark(key, 'error', `${U.theName(creatureName(r.enemy))} has no art variant "${r.variant}"`);
      if (r.until != null && Number(r.until) <= (Number(r.t) || 0)) mark(key, 'error', `until (${fmtT(r.until)}) is not after t (${fmtT(r.t)})`);
      if ((Number(r.t) || 0) < 0) mark(key, 'error', 't is negative');
      if (r.weight != null && Number(r.weight) < 0) mark(key, 'error', 'a negative weight');
      if (r.weights != null) {
        if (!Array.isArray(r.weights) || r.weights.some((p) => !isPair(p))) mark(key, 'error', 'a presence point is not [seconds, weight]');
        else {
          if (r.weights.some((p) => Number(p[1]) < 0)) mark(key, 'error', 'a negative presence weight');
          if (!inOrder(r.weights)) mark(key, 'warn', 'the presence points are not in time order (Save sorts them)');
          if (r.weights.length && r.weights.every((p) => Number(p[1]) === 0)) mark(key, 'warn', 'every presence point is 0: the row never spawns');
        }
      }
      if (typeof r.id === 'string') {
        if (ids.has(r.id)) mark(key, 'error', `the row id "${r.id}" is used twice (rows ${ids.get(r.id) + 1} and ${i + 1})`);
        else ids.set(r.id, i);
      }
      if (r.channel === 'hell' && !(d.hell_cap || []).some((h) => Number(h) > 0)) mark(key, 'warn', 'a hell row, but hell_cap is 0 on every stage: it never spawns');
      statsIssues(r.stats, key, mark, '');
    });
    (d.waves || []).forEach((w, i) => {
      const key = `wave:${i}`;
      const t = Number(w.t) || 0, count = Number(w.count) || 0, burst = Number(w.burst == null ? 5 : w.burst), every = Number(w.every == null ? 2 : w.every);
      const alts = Array.isArray(w.alts) ? w.alts : [];
      if (alts.length) {
        if (alts.every((a) => !(Number(a.chance) > 0))) mark(key, 'error', 'every alternative has chance 0: nothing can be rolled');
        alts.forEach((a, k) => {
          if (!creature(a.enemy)) mark(key, 'error', `alternative ${k + 1}: unknown creature "${a.enemy || ''}"`);
          else if (!variantOk(a.enemy, a.variant)) mark(key, 'error', `alternative ${k + 1}: ${U.theName(creatureName(a.enemy))} has no art variant "${a.variant}"`);
          statsIssues(a.stats, key, mark, `alternative ${k + 1}: `);
        });
      } else if (!creature(w.enemy)) mark(key, 'error', `unknown creature "${w.enemy || ''}" (no alternatives either)`);
      else if (!variantOk(w.enemy, w.variant)) mark(key, 'error', `${U.theName(creatureName(w.enemy))} has no art variant "${w.variant}"`);
      if (!alts.length) statsIssues(w.stats, key, mark, '');
      if (count === 0 && (w.until == null || w.until === '')) mark(key, 'warn', 'count 0 and no until: the wave runs forever');
      if (burst < 1) mark(key, 'error', 'burst must be at least 1');
      if (burst > hard) mark(key, 'error', `burst ${burst} is over the hard cap (${hard})`);
      if (every <= 0 && count > burst) mark(key, 'error', 'every is 0 with more than one burst to send');
      if (w.until != null && w.until !== '' && Number(w.until) <= t) mark(key, 'error', `until (${fmtT(w.until)}) is not after t (${fmtT(t)})`);
      if (count < 0) mark(key, 'error', 'a negative count');
      if (w.elite && w.elite !== 'random' && !elite(w.elite)) mark(key, 'error', `unknown elite modifier "${w.elite}"`);
      if (w.respect_cap === false && burst > 40) mark(key, 'warn', `${burst} at once on top of the cap`);
    });
    const bosses = (d.events || []).filter((e) => e.type === 'boss').map((e) => Number(e.t) || 0);
    (d.events || []).forEach((ev, i) => {
      const key = `event:${i}`;
      const t = Number(ev.t) || 0;
      if (!FIELDS.EVENT_TYPES[ev.type]) mark(key, 'error', `unknown event type "${ev.type}"`);
      const ids2 = U.idList(ev.enemy);
      for (const id of ids2) if (!creature(id)) mark(key, 'error', `unknown creature "${id}"`);
      if (ids2.length && ev.variant && !ids2.every((id) => variantOk(id, ev.variant))) mark(key, 'error', `art variant "${ev.variant}" is not one of every listed creature's`);
      if (Array.isArray(ev.weights) && ev.weights.length !== ids2.length) mark(key, 'warn', `${ev.weights.length} weights for ${ids2.length} creatures`);
      if (ev.type === 'boss' && !ids2.length) mark(key, 'warn', 'no boss named: the map\'s own boss comes');
      if (ev.type === 'elite_boss' && !ids2.length) mark(key, 'error', 'an Elite event needs a creature');
      if (ev.type === 'elite' && ev.mod && !elite(ev.mod)) mark(key, 'error', `unknown elite modifier "${ev.mod}"`);
      if (ev.type === 'elite_every') {
        const iv = ev.interval;
        const lo = Array.isArray(iv) ? Number(iv[0]) : Number(iv == null ? 90 : iv);
        if (!(lo > 0)) mark(key, 'error', 'the interval must be above 0');
      }
      if (ev.type === 'swarm' && Number(ev.count || 40) > hard) mark(key, 'error', `a swarm of ${ev.count} is over the hard cap (${hard})`);
      if (ev.chance != null && (Number(ev.chance) < 0 || Number(ev.chance) > 1)) mark(key, 'error', 'chance must be between 0 and 1');
      if (ev.chance != null && Number(ev.chance) === 0) mark(key, 'warn', 'chance 0: it never happens');
      statsIssues(ev.stats, key, mark, '');
      if (ev.type === 'boss' && t > 0 && Math.abs(t / SL - Math.round(t / SL)) > 1e-6) mark(key, 'warn', `a boss away from a stage boundary (${fmtT(SL)} × n): the portal after it starts the next stage early`);
      if (ev.type !== 'boss') {
        for (const bt of bosses) {
          if (t >= bt && t < bt + BOSS_WINDOW && stageAt(bt) === stageAt(t)) {
            mark(key, 'warn', `inside the boss fight at ${fmtT(bt)}: the clock stands still through it, so this fires as the next stage starts`);
            break;
          }
        }
      }
      if (t > runEnd()) mark(key, 'warn', 'past the last stage: only reached in endless');
    });
    const cc = d.cap_curve || [];
    if (!inOrder(cc.filter(isPair))) mark('cap', 'warn', 'the cap curve is not in time order (Save sorts it)');
    if (cc.some((p) => !isPair(p))) mark('cap', 'error', 'a cap point is not [seconds, cap]');
    if (d.hard_cap != null && d.cap_max != null && Number(d.hard_cap) < Number(d.cap_max)) mark('cap', 'warn', `hard_cap (${d.hard_cap}) is under cap_max (${d.cap_max}): the hard cap wins`);
    validateCurve('hp', d.hp_curve, mark, 'the HP curve');
    validateCurve('dmg', d.damage_curve, mark, 'the damage curve');
    const ss = d.spawn_sides;
    if (ss != null) {
      if (!U.isObj(ss)) mark('settings', 'error', 'spawn_sides must be a block {mode, top, bottom, left, right, ...}');
      else {
        if (ss.mode != null && ss.mode !== 'sides' && ss.mode !== 'facing') mark('settings', 'error', `spawn_sides: mode "${ss.mode}" is neither sides nor facing`);
        for (const k of ['top', 'bottom', 'left', 'right']) if (ss[k] != null && Number(ss[k]) < 0) mark('settings', 'error', `spawn_sides: a negative ${k} weight`);
        if (ss.mode === 'sides' && !['top', 'bottom', 'left', 'right'].some((k) => Number(ss[k]) > 0)) mark('settings', 'warn', 'spawn_sides: screen sides with every weight 0: the game plays the facing rule');
      }
    }
    (d.path_times || []).forEach((list, s) => {
      if (!Array.isArray(list)) { mark('paths', 'error', `path_times for stage ${s + 1} is not a list`); return; }
      for (const v of list) if (Number(v) < 0 || Number(v) > SL) { mark('paths', 'warn', `a path time (${v}) is outside stage ${s + 1} (0–${SL} s)`); break; }
    });
    const sp = d.specials || {};
    for (const row of sp.pool || []) {
      const id = typeof row === 'string' ? row : row.enemy;
      if (!creature(id)) mark('specials', 'error', `unknown special "${id}"`);
    }
    for (const row of ((d.pickups || {}).roster || [])) if (!pickup(row.id)) mark('pickups', 'warn', `unknown power-up "${row.id}"`);
    if (!(Number(d.stage_length) > 0)) mark('settings', 'error', 'stage_length must be above 0');
    S.issues = { errors, warnings, marks };
    return S.issues;
  }

  const issuesFor = (key) => (S.issues.marks[key] ? S.issues.marks[key] : null);

  // ------------------------------------------------------------------ save / revert / export

  /** What Save tidies before it writes: every point list in time order (the director's lerp walks them in order), a
   *  row with presence keyframes without the old weight keys. Returns true when anything changed. */
  function tidy(d) {
    const before = JSON.stringify(d);
    sortPoints(d.cap_curve);
    for (const r of d.roster || []) {
      if (Array.isArray(r.weights) && r.weights.length) { sortPoints(r.weights); delete r.weight; delete r.weight_late; }
    }
    for (const k of ['hp_curve', 'damage_curve']) if (U.isObj(d[k])) sortPoints(d[k].points);
    return JSON.stringify(d) !== before;
  }

  async function save() {
    if (assetDoc()) { await Assets.save(S.tab); return; }
    if (!S.map || S.saving) return;
    const issues = validate();
    if (issues.errors.length) {
      status(`Cannot save: ${issues.errors.length} error${issues.errors.length > 1 ? 's' : ''} (see the inspector)`, 'bad');
      render('all');
      return;
    }
    if (!dirty()) { status('Nothing to save'); return; }
    { const before = snapshot(); if (tidy(S.tl)) pushHistory(before); }
    S.saving = true;
    status('Saving and importing…', 'busy');
    updateTopBar();
    try {
      const r = await fetch('/api/map/' + S.mapId, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(S.map) });
      const res = await r.json();
      if (!res.ok) throw new Error(res.error || `HTTP ${r.status}`);
      S.saved = JSON.stringify(S.map);
      const when = new Date().toLocaleTimeString();
      if (res.import_ok) status(`Saved ${res.wrote} at ${when} · import OK · backup ${res.backup.split('/').pop()}`, 'good', res.output);
      else status(`Saved ${res.wrote} at ${when} · IMPORT FAILED (the game still plays the old .tres)`, 'bad', res.output);
    } catch (e) {
      status('Save failed: ' + e.message, 'bad');
    }
    S.saving = false;
    render('all');
  }

  function revert() {
    if (assetDoc()) { Assets.revert(S.tab); return; }
    if (!S.map || !dirty()) { status('Nothing to revert'); return; }
    const before = snapshot();
    S.map = JSON.parse(S.saved);
    S.tl = S.map.timeline_data;
    pushHistory(before);
    if (S.sel && !selected()) S.sel = null;
    status('Reverted to the saved file');
    render('all');
  }

  function exportJson() {
    if (!S.map) return;
    const copy = JSON.parse(snapshot());
    tidy(copy.timeline_data || {});
    U.download(`${S.mapId}.json`, JSON.stringify(copy, null, 2) + '\n');
    status('Exported a copy (your browser\'s downloads)');
  }

  // ------------------------------------------------------------------ rendering

  // pass 66: the asset tabs (Heroes, Items, Jobs; `Assets.owns`) draw without a map and keep their own documents
  function assetsTab(tab) {
    return typeof Assets !== 'undefined' && Assets.owns(tab || S.tab);
  }

  function render(what) {
    if (!S.map && !assetsTab()) return;
    if (S.map) validate();
    const w = what || 'all';
    if (w === 'none') { updateTopBar(); return; }
    if (S.tab === 'timeline') {
      if (w === 'all' || w === 'timeline' || w === 'selection') Timeline.render();
      if (w === 'all' || w === 'inspector' || w === 'selection') Inspector.render(document.getElementById('inspector'));
    } else if (w === 'all' || w === 'tab') {
      const panel = document.getElementById('tab-' + S.tab);
      if (S.tab === 'settings') Settings.render(panel);
      else if (S.tab === 'creatures') Creatures.render(panel);
      else if (S.tab === 'instructions') Instructions.render(panel);
      // pass 72 (lane BOSS): the custom boss attacks (boss_attacks.js keeps its own documents and keys)
      else if (S.tab === 'bossattacks' && typeof BossAttacks !== 'undefined') BossAttacks.render(panel);
      else if (assetsTab()) Assets.render(S.tab, panel);
    }
    updateTopBar();
  }

  function updateTopBar() {
    const mapName = document.getElementById('map-name');
    const saveBtn = document.getElementById('btn-save');
    if (assetDoc()) {
      // pass 66: the open asset document's state; the map keeps its own unsaved mark on its name
      const doc = Assets.active(S.tab);
      const ad = Assets.docDirty(doc);
      const aiss = Assets.issuesOf(doc);
      saveBtn.disabled = !ad || doc.saving;
      saveBtn.textContent = doc.saving ? 'Saving…' : 'Save asset';
      saveBtn.title = aiss.errors.length ? `${aiss.errors.length} error(s) block the save of ${doc.id}` : `Write ${doc.id}.json and import it (Ctrl+S)`;
      saveBtn.classList.toggle('blocked', ad && aiss.errors.length > 0);
      document.getElementById('btn-revert').disabled = !ad;
      document.getElementById('dirty-dot').hidden = !ad;
      document.getElementById('dirty-dot').title = `unsaved changes to ${doc.id}`;
      document.getElementById('btn-undo').disabled = !doc.history.length;
      document.getElementById('btn-redo').disabled = !doc.future.length;
      if (mapName) { mapName.classList.toggle('map-dirty', dirty()); mapName.title = dirty() ? 'the map has unsaved changes (back on the Timeline or Settings tab to save it)' : ''; }
      const aissEl = document.getElementById('issues');
      const ane = aiss.errors.length, anw = aiss.warnings.length;
      aissEl.textContent = ane || anw ? `${doc.id}: ${ane ? ane + ' error' + (ane > 1 ? 's' : '') : ''}${ane && anw ? ' · ' : ''}${anw ? anw + ' warning' + (anw > 1 ? 's' : '') : ''}` : `${doc.id}: no issues`;
      aissEl.className = 'issues ' + (ane ? 'bad' : anw ? 'warn' : 'good');
      return;
    }
    if (mapName) { mapName.classList.remove('map-dirty'); mapName.title = ''; }
    const d = dirty();
    saveBtn.disabled = !d || S.saving;
    saveBtn.textContent = S.saving ? 'Saving…' : 'Save';
    saveBtn.title = S.issues.errors.length ? `${S.issues.errors.length} error(s) block the save` : 'Write the JSON and import it (Ctrl+S)';
    saveBtn.classList.toggle('blocked', d && S.issues.errors.length > 0);
    document.getElementById('btn-revert').disabled = !d;
    document.getElementById('dirty-dot').hidden = !d;
    document.getElementById('dirty-dot').title = 'unsaved changes';
    document.getElementById('btn-undo').disabled = !S.history.length;
    document.getElementById('btn-redo').disabled = !S.future.length;
    const iss = document.getElementById('issues');
    const ne = S.issues.errors.length, nw = S.issues.warnings.length;
    iss.textContent = ne || nw ? `${ne ? ne + ' error' + (ne > 1 ? 's' : '') : ''}${ne && nw ? ' · ' : ''}${nw ? nw + ' warning' + (nw > 1 ? 's' : '') : ''}` : 'no issues';
    iss.className = 'issues ' + (ne ? 'bad' : nw ? 'warn' : 'good');
  }

  /** The status line; `detail` (the import's output) unfolds under it on a failure, or on a click on the line. */
  function status(msg, kind, detail) {
    const s = document.getElementById('status');
    s.textContent = msg;
    s.className = 'status ' + (kind || '') + (detail ? ' has-detail' : '');
    s.title = detail ? 'click for the import output' : '';
    const d = document.getElementById('status-detail');
    if (d) { d.textContent = detail || ''; d.hidden = !(detail && kind === 'bad'); }
  }

  function setClock(t, extra) {
    const c = document.getElementById('clock');
    if (t == null) { c.textContent = ''; return; }
    c.textContent = `${fmtT(t)} · ${stageName(stageAt(t))} · cap ${capAt(t)}${extra ? ' · ' + extra : ''}`;
  }

  // ------------------------------------------------------------------ toasts

  function toast(msg, opts) {
    const host = document.getElementById('toasts');
    const o = opts || {};
    const t = el('div', { class: 'toast' }, el('span', { text: msg }));
    if (o.undo) t.appendChild(el('button', { class: 'btn small', text: 'Undo', onclick: () => { undo(); t.remove(); } }));
    host.appendChild(t);
    setTimeout(() => t.classList.add('show'), 10);
    setTimeout(() => { t.classList.remove('show'); setTimeout(() => t.remove(), 300); }, o.ms || 6000);
  }

  // ------------------------------------------------------------------ top bar, tabs, keys

  function wireTopBar() {
    document.getElementById('btn-save').addEventListener('click', save);
    document.getElementById('btn-revert').addEventListener('click', revert);
    document.getElementById('btn-export').addEventListener('click', exportJson);
    document.getElementById('btn-undo').addEventListener('click', undo);
    document.getElementById('btn-redo').addEventListener('click', redo);
    document.getElementById('zoom-in').addEventListener('click', () => Timeline.zoom(0.7));
    document.getElementById('zoom-out').addEventListener('click', () => Timeline.zoom(1 / 0.7));
    document.getElementById('zoom-fit').addEventListener('click', () => Timeline.fit());
    // pass 61: the Snap toggle (S too); timeline.js keeps the state and the browser remembers it
    const snapBtn = document.getElementById('snap-toggle');
    if (snapBtn) snapBtn.addEventListener('click', () => Timeline.toggleSnap());
    document.getElementById('status').addEventListener('click', () => { const d = document.getElementById('status-detail'); if (d && d.textContent) d.hidden = !d.hidden; });
    // the hero level the hover cards and the readout assume (pass 54): a page setting, never written to the map
    const lv = document.getElementById('assume-level');
    if (lv) {
      try { const saved = Number(localStorage.getItem('88fits-editor-level')); if (saved >= 1) { S.level = Math.min(99, Math.round(saved)); lv.value = S.level; } } catch (_) { /* no storage: level 1 */ }
      lv.addEventListener('change', () => {
        const v = Math.max(1, Math.min(99, Math.round(Number(lv.value) || 1)));
        lv.value = v; S.level = v;
        try { localStorage.setItem('88fits-editor-level', String(v)); } catch (_) { /* fine */ }
        render('all');
      });
      lv.addEventListener('keydown', (e) => { if (e.key === 'Enter') lv.blur(); });
    }
    window.addEventListener('beforeunload', (e) => { if (dirty() || (typeof Assets !== 'undefined' && Assets.anyDirty())) { e.preventDefault(); e.returnValue = ''; } });
  }

  // only the buttons that carry data-tab: the zoom buttons share the nav (a click on "+" once switched to no tab at all)
  function wireTabs() {
    for (const b of document.querySelectorAll('.tabs button[data-tab]')) b.addEventListener('click', () => switchTab(b.dataset.tab));
  }

  function switchTab(name) {
    S.tab = name;
    for (const b of document.querySelectorAll('.tabs button[data-tab]')) b.classList.toggle('active', b.dataset.tab === name);
    for (const p of document.querySelectorAll('.tab-panel')) p.hidden = p.id !== 'tab-' + name;
    document.getElementById('zoom-box').hidden = name !== 'timeline';
    if (Timeline.hideCard) Timeline.hideCard();
    render(name === 'timeline' ? 'all' : 'tab');
  }

  function wireKeys() {
    window.addEventListener('keydown', (e) => {
      const tgt = e.target;
      const typing = tgt && (tgt.tagName === 'INPUT' || tgt.tagName === 'TEXTAREA' || tgt.tagName === 'SELECT' || tgt.isContentEditable);
      const ctrl = e.ctrlKey || e.metaKey;
      // a box still being typed in commits first, so Ctrl+S saves what it shows (pass 58 review)
      if (ctrl && e.key.toLowerCase() === 's') { e.preventDefault(); if (typing && typeof tgt.blur === 'function') tgt.blur(); save(); return; }
      if (typing) { if (e.key === 'Escape') tgt.blur(); return; }
      if (ctrl && e.key.toLowerCase() === 'z' && !e.shiftKey) { e.preventDefault(); undo(); return; }
      if (ctrl && (e.key.toLowerCase() === 'y' || (e.key.toLowerCase() === 'z' && e.shiftKey))) { e.preventDefault(); redo(); return; }
      if (S.tab !== 'timeline') return;
      if (ctrl && e.key.toLowerCase() === 'd') { e.preventDefault(); duplicateSelected(); return; }
      if (e.key === 'Delete' || e.key === 'Backspace') { if (S.sel && S.sel.i != null) { e.preventDefault(); deleteSelected(); } return; }
      if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
        if (!S.sel || S.sel.i == null) return;
        e.preventDefault();
        nudge((e.key === 'ArrowLeft' ? -1 : 1) * (e.shiftKey ? 10 : 1));
        return;
      }
      // Alt + up / down moves the selected roster row (pass 54)
      if (e.altKey && (e.key === 'ArrowUp' || e.key === 'ArrowDown') && S.sel && S.sel.kind === 'roster') {
        e.preventDefault();
        moveRow(S.sel.i, e.key === 'ArrowUp' ? -1 : 1);
        return;
      }
      if (e.key === 'Escape') { select(null); return; }
      // pass 61: S switches snapping (Ctrl+S saves, above); not when a focused picture list took the letter as its filter
      if (!ctrl && !e.altKey && !e.defaultPrevented && e.key.toLowerCase() === 's') { e.preventDefault(); toast(Timeline.toggleSnap() ? 'Snap on: dragged times drop onto the cap\'s points, the rows, waves and events (hold Alt to drag freely)' : 'Snap off: dragged times move freely', { ms: 2500 }); return; }
      if (e.key === '+' || e.key === '=') Timeline.zoom(0.7);
      if (e.key === '-') Timeline.zoom(1 / 0.7);
    });
  }

  document.addEventListener('DOMContentLoaded', init);

  return {
    S, init, loadMap, refreshCreatures, creature, creatureName, elite, pickup, variantOk, iconFor, playCode, creatureColor,
    tl, stageLength, stages, runEnd, viewEnd, stageAt, stageName, stageMult, samplePoints, capAt, hellCapAt,
    hpTimeMult, dmgTimeMult, hpMultAt, dmgMultAt, creatureAt, rowNumbers, eventNumbers, sourceName, actual, actualAt, knockbackOf, rowWeight, rosterAt, waveEnd, wavesAt, nextEvent,
    eventLabel, eventShares, waveAlts, snapshot, pushHistory, apply, undo, redo, dirty, selected, select, selKey, newWave,
    newRow, newEvent, deleteSelected, duplicateSelected, moveRow, moveRowTo, shiftWeights, sortPoints, nudge, validate,
    issuesFor, save, revert, exportJson, render, status, setClock, toast, switchTab, BOSS_WINDOW,
    spawned, spawnOpts, setAssume, turnoverSource,
  };
})();
