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
    sel: null,                  // {kind: 'roster'|'wave'|'event'|'cap'|'hp'|'dmg'|'specials'|'paths'|'pickups', i}
    tab: 'timeline',
    enemies: [], byId: {}, elites: [], pickups: [], schema: '',
    issues: { errors: [], warnings: [], marks: {} },
    saving: false,
    level: 1,                   // the hero level the hover cards and the readout assume (pass 54)
    enemiesRev: 0,              // bumped whenever the creature list is read again (the estimate's cache key)
    fit: null,                  // pass 57: the server's kill rate, boss fight and portal wait from the run records
    assume: { turnover: null, bossSeconds: null, portalSeconds: null },  // pass 57: the page's own numbers (null = the fit)
    simLife: null,              // pass 84: the shown Sim's lifetimes {creature id: mean seconds alive} (Timeline's overlay)
    useSimLife: false,          // pass 84: the estimate takes them (Ruler and controls: "lifetimes from the Sim")
    stageView: 'all',           // pass 87 (lane STOOLS): the Timeline's stage tab: 'all' (the whole map) or a stage index
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
    initRoutes();   // pass 97 (lane LIVE): a reload returns to the tab, the job, the request or the frame the address names
  }

  // ------------------------------------------------------------------ pass 97 (lane LIVE, UI-02): the page's routes
  // The address's hash names where the page is: #<tab>, #jobs/<id>, #jobs?look=SP-B&id=<creature>, #requests/<rid>,
  // #frames/<kind>/<id>/<code>/<anim>/<view>/<slot> (JobsModel.parseHash / formatHash). It is written as the page moves
  // (replaceState: no history entries, Back behaves as before) and read once on load and on a link's hashchange, so a
  // reload comes back to the same tab, card, request or frame. An address without a hash opens the Timeline as before.
  let routing = false;
  function routeModel() { return typeof JobsModel !== 'undefined' && JobsModel.parseHash ? JobsModel : null; }
  /** Write the hash for a route ({tab} | {tab, job} | {tab, request} | {tab, filter} | {tab, frames}). */
  function route(r) {
    const RM = routeModel();
    if (!RM || routing || typeof history === 'undefined' || !history.replaceState) return;
    const h = RM.formatHash(r) || '';
    if ((location.hash || '') === h) return;
    try { history.replaceState(history.state, '', location.pathname + location.search + h); } catch (_) { /* a page without a history: the hash stays */ }
  }
  /** Where the page is now, as a route (the tab; on the Jobs tab its filter). */
  function here() {
    if (S.tab === 'jobs' && typeof Jobs !== 'undefined' && Jobs.S && Jobs.S.filter) return { tab: 'jobs', filter: Jobs.S.filter };
    return { tab: S.tab };
  }
  async function applyRoute(r) {
    if (!r) return;
    routing = true;
    try {
      if (r.tab && r.tab !== S.tab && document.querySelector(`.tabs button[data-tab="${r.tab}"]`)) switchTab(r.tab);
      if (r.tab === 'jobs' && typeof Jobs !== 'undefined') {
        if (r.job) Jobs.focus(r.job);
        else if (r.request) Jobs.focusRequest(r.request);
        else if (r.filter) Jobs.setFilter(r.filter);
        else if (Jobs.S && Jobs.S.filter) Jobs.setFilter(null);
      }
      if (r.frames && typeof Frames !== 'undefined') {
        const f = r.frames;
        if (typeof Assets !== 'undefined' && typeof Assets.open === 'function') { try { await Assets.open(f.kind, f.id); } catch (_) { /* the view opens all the same */ } }
        const viewer = await Frames.open(f.kind, f.id, f.code, { base: f.anim, view: f.view, slot: f.slot });
        // the address named a frame: the view stays on it (a loop would otherwise play on from it)
        if (viewer && f.slot != null && typeof viewer.pause === 'function' && typeof viewer.showPos === 'function') { viewer.pause(); viewer.showPos(f.slot); }
      }
    } finally { routing = false; }
    route(r);
  }
  /** The Frames view writes its group and slot into the address while it is open (a paused frame's slot; a playing view
   *  its animation and view), and the address goes back to where the page was when it closes. frames.js is not changed:
   *  Frames.open is wrapped once here. */
  function routeFrames() {
    if (typeof Frames === 'undefined' || typeof Frames.open !== 'function' || Frames.__routed) return;
    const open = Frames.open;
    Frames.open = async function (kind, id, code, o) {
      const back = here();
      const opts = o || {};
      route({ frames: { kind, id, code, anim: opts.base, view: opts.view, slot: opts.slot } });
      let viewer = null;
      try { viewer = await open.call(Frames, kind, id, code, o); } catch (e) { route(back); throw e; }
      const dlg = viewer && viewer.dlg;
      if (!dlg) { route(back); return viewer; }
      const tick = setInterval(() => {
        if (!dlg.isConnected) { clearInterval(tick); return; }
        route({ frames: { kind, id, code, anim: viewer.base || undefined, view: viewer.view || undefined, slot: viewer.playing ? undefined : viewer.slot } });
      }, 1000);
      dlg.addEventListener('close', () => { clearInterval(tick); route(here()); });
      return viewer;
    };
    Frames.__routed = true;
  }
  function initRoutes() {
    const RM = routeModel();
    if (!RM) return;
    routeFrames();
    window.addEventListener('hashchange', () => { const r = RM.parseHash(location.hash); if (r) applyRoute(r); });
    const r = RM.parseHash(location.hash);
    if (r) applyRoute(r); else route(here());
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
      // pass 84 (lane TIMELINE): one spawning language: swarm, coloured-elite and Elites-every events and the waves[]
      // blocks become spawn rows on load (lane SPAWN's converter; the game still plays an old file as before), and Save
      // writes the rows. A map with none of them is left exactly as it is (no churn)
      const legacy = legacyConvert(map.timeline_data);
      S.mapId = id; S.map = map; S.tl = map.timeline_data;
      S.saved = JSON.stringify(map);
      S.history = []; S.future = []; S.sel = null;
      document.getElementById('map-select').value = id;
      document.getElementById('map-name').textContent = map.name || id;
      document.title = `${map.name || id} · 88fits Level Editor`;
      const m = S.maps.find((x) => x.id === id);
      document.getElementById('map-file').textContent = m ? m.file : '';
      const note = conv.converted || conv.ided ? ` · ${conv.converted ? `${conv.converted} roster rows read from weight / weight_late as presence keyframes` : ''}${conv.converted && conv.ided ? ', ' : ''}${conv.ided ? `${conv.ided} rows given an id` : ''} (the next Save writes the new shape)` : '';
      status(`Loaded ${m ? m.file : id}${note}${legacy}`);
      loadAssume(id);
      loadStageView(id);
      S.fit = null;
      fetchFit(id);
      render('all');
      if (Timeline.fit) Timeline.fit();
      // pass 84: the newest finished Sim of this map for the view lanes (Ruler and controls picks another)
      if (Timeline.loadSimList) Timeline.loadSimList(true);
    } catch (e) {
      status('Could not load the map: ' + e.message, 'bad');
    }
  }

  /** Pass 84 (lane TIMELINE): the old ways to spawn (swarm, elite, elite_every events, the waves[] list) as spawn rows,
   *  through lane SPAWN's Model.convertLegacy (it changes `tl` in place and says what it did); nothing when the model has
   *  no converter yet or the map has nothing old. Returns the status line's words. */
  function legacyConvert(tld) {
    const old = (Array.isArray(tld.events) ? tld.events : []).filter((e) => e && ['swarm', 'elite', 'elite_every'].includes(e.type)).length + (Array.isArray(tld.waves) ? tld.waves.length : 0);
    if (!old || typeof M.convertLegacy !== 'function') return '';
    try {
      const before = JSON.stringify(tld);
      const skins = S.map && U.isObj(S.map.skins) ? Object.values(S.map.skins) : [];
      const res = M.convertLegacy(tld, { skin: skins.length ? String(skins[0]) : '' });
      if (JSON.stringify(tld) === before) return '';
      const n = res && typeof res === 'object' && res.converted != null ? res.converted : old;
      return ` · ${n} old swarm / elite events and wave blocks read as spawn rows (the next Save writes them; the game plays both alike)`;
    } catch (e) {
      console.error('convertLegacy', e);
      return ' · the old events could not be converted (they still play)';
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
  // pass 87 (lane STOOLS): the stage windows (stage_list) and the Timeline's stage tabs
  const stageList = () => M.stageList(tl());
  const stageStart = (s) => M.stageStart(tl(), s);
  const stageEnd = (s) => M.stageEnd(tl(), s);
  const stageLen = (s) => M.stageLen(tl(), s);
  const stageWindow = (s) => M.stageWindow(tl(), s);
  /** The stage tab open on the Timeline: null for "All", else the 0-based stage (a tab past the stages falls back). */
  const viewStage = () => (typeof S.stageView === 'number' && S.stageView >= 0 && S.stageView < stages() ? S.stageView : null);
  /** Seconds after a stage's boss the view shows (the portal's timer, then a little Endless). */
  /** The portal's countdown after the open stage's boss (the map's endless.portal_seconds; a stage's own block wins). */
  const portalSeconds = () => M.portalTimer(tl(), viewStage() == null ? stages() - 1 : viewStage());
  const AFTER_STAGE = 120;
  /** The run clock where the view starts: 0, or the open stage's window start. */
  const viewStart = () => (viewStage() == null ? 0 : stageStart(viewStage()));
  /** The axis runs a little into endless, so open rows and timers show where they go on; a stage tab shows its window,
   *  the portal's timer after its boss and two minutes of Endless. */
  const viewEnd = () => (viewStage() == null
    ? runEnd() + Math.max(120, Math.round(stageLen(stages() - 1) * 0.35))
    : stageEnd(viewStage()) + portalSeconds() + AFTER_STAGE);
  const stageViewKey = (id) => `88fits-editor-stageview-${id}`;
  /** Open a stage tab (null / 'all' = the whole map); the browser remembers it per map. */
  function setStageView(v) {
    S.stageView = v == null || v === 'all' ? 'all' : Math.max(0, Math.min(Math.floor(Number(v)), stages() - 1));
    try { localStorage.setItem(stageViewKey(S.mapId), String(S.stageView)); } catch (_) { /* fine */ }
  }
  function loadStageView(id) {
    S.stageView = 'all';
    try { const v = localStorage.getItem(stageViewKey(id)); if (v != null && v !== 'all' && isFinite(Number(v))) S.stageView = Number(v); } catch (_) { /* all */ }
  }
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

  /** Pass 103 (lane LE): the cap the curve asks for at t before cap_max cuts it (the curve plus cap_per_stage). */
  function capRawAt(t) {
    return Math.max(0, Math.floor(curveAt(t) + (Number(tl().cap_per_stage) || 0) * stageAt(t)));
  }

  /** Pass 103 (lane LE): the highest the cap curve asks for over the run (control points and the stage steps), and
   *  cap_max: {raw, max (Infinity when none), cut (true when cap_max is under the curve somewhere)}. */
  function capCut() {
    const d = tl();
    const mx = d.cap_max == null || d.cap_max === '' ? Infinity : Number(d.cap_max);
    let raw = 0;
    const end = runEnd();
    const ts = [0, end].concat((d.cap_curve || []).filter((p) => Array.isArray(p)).map((p) => Math.min(Number(p[0]) || 0, end)));
    for (const w of stageList()) ts.push(w.start, Math.max(w.start, w.end - 1e-3));
    for (const t of ts) raw = Math.max(raw, capRawAt(t));
    return { raw, max: mx, cut: isFinite(mx) && raw > mx };
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
      // pass 81 (lane PACE): `paced` a row that comes as waves, `drawn` one in the continuous draw (norm 0 when not)
      if (t >= start && t < until) open.push({ row: r, i, w: rowWeight(r, t), hell: r.channel === 'hell', paced: M.rowPaced(r), drawn: M.rowDrawn(r), norm: 0 });
    });
    for (const ch of [false, true]) {
      const part = open.filter((o) => o.hell === ch && o.drawn);
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
      // pass 84 (lane SPAWN's estimate): the creatures the Sim measured leave the crowd after their measured lifetime,
      // the rest by the kill rate (only when "lifetimes from the Sim" is ticked)
      life: S.useSimLife && S.simLife ? S.simLife : null,
      turnover,
      bossSeconds: a.bossSeconds != null ? a.bossSeconds : (f.boss_seconds != null ? f.boss_seconds : M.EST_DEF.bossSeconds),
      portalSeconds: a.portalSeconds != null ? a.portalSeconds : (f.portal_seconds != null ? f.portal_seconds : M.EST_DEF.portalSeconds),
      skin: skins.length ? String(skins[0]) : '',
      boss: S.map && S.map.boss ? String(S.map.boss) : '',
      end: viewEnd(),
      // pass 87 (lane STOOLS): the open stage tab's run (null on All)
      stage: viewStage(),
    };
  }

  /** Pass 84: the Timeline's Sim overlay hands its measured lifetimes ({id: seconds}, null without a Sim). */
  function setSimLife(life) {
    S.simLife = life && Object.keys(life).length ? life : null;
  }
  /** Pass 84: whether the estimate takes the Sim's lifetimes (a page setting the browser remembers). */
  function setUseSimLife(on) {
    S.useSimLife = !!on;
    try { localStorage.setItem('88fits-editor-simlife', S.useSimLife ? '1' : '0'); } catch (_) { /* fine */ }
    render('all');
  }
  try { S.useSimLife = localStorage.getItem('88fits-editor-simlife') === '1'; } catch (_) { /* off */ }

  /** Where the kill rate comes from, in words (the lane's label and its card). */
  function turnoverSource() {
    const f = S.fit;
    if (S.assume.turnover != null) return 'your number';
    if (S.useSimLife && S.simLife) return `the Sim's lifetimes (${Object.keys(S.simLife).length} creatures) and ${f && f.source === 'records' ? 'your runs' : 'the default'} for the rest`;
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
    // pass 87 (lane STOOLS): every stage is its own run: a stage tab estimates that stage's run (a fresh hero from its
    // window's start), "All" each stage's run stitched on the map's clock (a map without a stage list: the old one run)
    const est = opts.stage != null ? M.spawnEstimate(tl(), S.enemies, opts)
      : M.hasStageList(tl()) ? M.stagesEstimate(tl(), S.enemies, opts) : M.spawnEstimate(tl(), S.enemies, Object.assign({}, opts, { stage: null }));
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
    // pass 87: a stage's settings card
    if (s.kind === 'stage') return s.i != null && s.i >= 0 && s.i < stages() ? { kind: 'stage', i: s.i } : null;
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
      d.roster.push({ id: M.newRowId(d), t: at, enemy: id, weights: [[at, 5], [at + Math.round(stageLen(stageAt(at)) / 2), 5]] });
      S.sel = { kind: 'roster', i: d.roster.length - 1 };
    });
    toast(`Added a roster row at ${fmtT(at)}`);
  }

  /** Pass 84 (lane TIMELINE): "+ Row"'s kinds: a continuous row, a waves row, once (a swarm), a coloured elite (once,
   *  from the roster draw), Elites every (waves from the roster draw), a special (once). Each with a presence that holds
   *  its waves and the keys of INTERFACES.md, at the view's centre. */
  function newRowPreset(kind, t) {
    const id = firstCreatureId();
    const at = Math.max(0, Math.round(t == null ? Timeline.viewCenter() : t));
    // pass 87: half / a whole of the stage the row starts in
    const SL = stageLen(Math.min(stageAt(at), stages() - 1));
    const presets = {
      continuous: () => ({ enemy: id, weights: [[at, 5], [at + Math.round(SL / 2), 5]] }),
      waves: () => ({ enemy: id, weights: [[at, 5], [at + Math.round(SL / 2), 5]], until: at + Math.round(SL / 2), pace: 'waves', every: 30, count: 10, role: 'fodder' }),
      once: () => ({ name: `${creatureName(id)} swarm`, enemy: id, weights: [[at, 1], [at + 30, 1]], until: at + 30, pace: 'once', count: 30, respect_cap: false, pattern: 'ring', ring_radius: 16, banner: 'SWARM!', role: 'swarm' }),
      elite: () => ({ name: 'Coloured elite', enemy: 'roster', weights: [[at, 1], [at + 30, 1]], until: at + 30, pace: 'once', count: 1, elite: 'random', role: 'elite' }),
      elite_every: () => ({ name: 'Elites every', enemy: 'roster', weights: [[at, 1], [at + SL, 1]], pace: 'waves', every: [110, 150], count: 1, elite: 'random', role: 'elite' }),
      special: () => ({ name: `Special ${creatureName(id)}`, enemy: id, weights: [[at, 1], [at + 30, 1]], until: at + 30, pace: 'once', count: 1, pattern: 'in_front', special: true, role: 'special' }),
    };
    const make = presets[kind] || presets.continuous;
    apply((d) => {
      if (!Array.isArray(d.roster)) d.roster = [];
      d.roster.push(Object.assign({ id: M.newRowId(d), t: at }, make()));
      S.sel = { kind: 'roster', i: d.roster.length - 1 };
    });
    toast(`Added a ${kind === 'elite_every' ? 'Elites-every' : kind === 'elite' ? 'coloured-elite' : kind} row at ${fmtT(at)}`);
  }

  /** Pass 84: split row i at run second t: this row ends at t, a copy (a fresh id) starts there with the presence points
   *  at and after t (the presence at t as its first point), so its numbers are fixed afresh from t. One undo step. */
  function splitRow(i, t) {
    const r = (tl().roster || [])[i];
    if (!r || t == null) return;
    const at = Math.round(Number(t));
    const t0 = Number(r.t) || 0, end = r.until == null || r.until === '' ? Infinity : Number(r.until);
    if (!(at > t0 && at < end)) { toast('Split where the row runs: hover its span first'); return; }
    apply((d) => {
      const row = d.roster[i];
      const copy = clone(row);
      copy.id = M.newRowId(d);
      copy.t = at;
      if (Array.isArray(row.weights) && row.weights.length) {
        const wAt = M.round(rowWeight(row, at), 2);
        copy.weights = [[at, wAt]].concat(row.weights.filter((p) => Number(p[0]) > at).map((p) => p.slice()));
        row.weights = row.weights.filter((p) => Number(p[0]) < at).map((p) => p.slice()).concat([[at, wAt]]);
        if (row.weights.length < 2) row.weights.unshift([t0, M.round(rowWeight(row, t0), 2)]);
        if (copy.weights.length < 2) copy.weights.push([Math.min(end === Infinity ? at + 60 : end, at + 60), wAt]);
      }
      row.until = at;
      if (String(copy.pace) === 'once') delete copy.pace;
      d.roster.splice(i + 1, 0, copy);
      S.sel = { kind: 'roster', i: i + 1 };
    });
    toast(`Split at ${fmtT(at)}: the second part's numbers are fixed from ${fmtT(at)}`, { undo: true });
  }

  /** Pass 84: a row paced another way: once (one wave at its start + offset), waves (every 30 s unless it has an Every),
   *  continuous (the waves keys go). One undo step. */
  function convertRow(i, pace) {
    const r = (tl().roster || [])[i];
    if (!r) return;
    apply(() => {
      if (pace === 'continuous') { delete r.pace; for (const k of M.ROW_WAVE_KEYS) delete r[k]; delete r.banner; delete r.chance; delete r.t_jitter; return; }
      r.pace = pace;
      if (pace === 'waves' && r.every == null) r.every = M.ROW_WAVE_EVERY_DEF;
      if (pace === 'once') delete r.every;
      if (r.count == null) r.count = M.rowWaveCount(r, creature(Array.isArray(r.enemy) ? r.enemy[0] : r.enemy));
    });
    toast(`Row ${r.id || i + 1} is ${pace === 'once' ? 'one wave now' : pace === 'waves' ? 'paced as waves now' : 'continuous now'}`, { undo: true });
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

  /** A roster row's pacing (pass 81, lane PACE): an unknown `pace` and a waves row's impossible numbers block Save; a
   *  first wave after the row's end, a wave faster than a second, a big wave off the cap, and the waves-only keys on a
   *  continuous row (the game ignores them) are warnings. */
  function paceIssues(r, key, mark, hard) {
    if (r.pace != null && !M.ROW_PACES.includes(String(r.pace)) && String(r.pace) !== 'once') mark(key, 'error', `unknown pacing "${r.pace}" (continuous, waves or once; the game plays it continuous)`);
    // pass 84: a once row carries the waves keys too (its one wave)
    if (!M.rowPaced(r) && String(r.pace) !== 'once') {
      const stray = M.ROW_WAVE_KEYS.filter((k) => r[k] != null);
      if (stray.length) mark(key, 'warn', `${stray.join(', ')} ${stray.length > 1 ? 'mean' : 'means'} nothing on a continuous row (Pacing): the game ignores ${stray.length > 1 ? 'them' : 'it'}`);
      return;
    }
    const t = Number(r.t) || 0;
    // pass 84: every may be [min, max] (a fresh random gap each wave)
    if (Array.isArray(r.every)) {
      const lo = Number(r.every[0]), hi = Number(r.every[r.every.length - 1]);
      if (r.every.length !== 2 || !(lo >= 0) || !(hi >= lo)) mark(key, 'error', 'every as a range is [min, max] seconds, min 0 or more and max at least min');
      else if (hi > 0 && lo < 1) mark(key, 'warn', `a wave as soon as every ${lo} s reads as continuous: use a longer minimum`);
    } else if (r.every != null && !(Number(r.every) >= 0)) mark(key, 'error', 'every must be 0 (one wave) or more seconds');
    else if (!Array.isArray(r.every) && r.every != null && Number(r.every) > 0 && Number(r.every) < 1) mark(key, 'warn', `a wave every ${r.every} s reads as continuous: use Continuous, or a longer Every`);
    if (r.offset != null && !(Number(r.offset) >= 0)) mark(key, 'error', 'offset must be 0 or more seconds');
    if (r.count != null && !(Number(r.count) >= 1)) mark(key, 'error', 'a wave brings at least 1 (Per wave)');
    const n = M.rowWaveCount(r, creature(r.enemy));
    if (n > hard) mark(key, 'error', `a wave of ${n} is over the hard cap (${hard})`);
    else if (r.respect_cap === false && n > 40) mark(key, 'warn', `${n} at once on top of the cap every wave`);
    if (r.until != null && r.until !== '' && M.rowWaveStart(r) >= Number(r.until)) mark(key, 'warn', `the first wave (${fmtT(M.rowWaveStart(r))}) is not before until (${fmtT(r.until)}): the row never spawns`);
    else if (!M.rowEtchTimes(r, Math.max(viewEnd(), t + 1), lateT()).length && M.rowWaveTimes(r, Math.max(viewEnd(), t + 1)).length) mark(key, 'warn', 'its presence is 0 at every wave: no wave comes');
  }

  /** A continuous row's own interval (pass 83, lane TIMELINE): not a number above 0 blocks Save (the game would draw the
   *  row at the spawn check); under ROW_INTERVAL_MIN, on a row not in the continuous draw (the game ignores it) and a
   *  draw much faster than the spawn check are warnings. */
  function intervalIssues(r, key, mark) {
    if (r.interval == null || r.interval === '') return;
    if (!M.rowHasInterval(r)) { mark(key, 'error', `draw every must be a number of seconds above 0 (got ${JSON.stringify(r.interval)}; the game would draw the row at the spawn check)`); return; }
    if (!M.rowDrawn(r)) mark(key, 'warn', 'draw every means nothing on a row paced as waves that is not Also continuous: the game ignores it');
    if (r.interval < M.ROW_INTERVAL_MIN) mark(key, 'warn', `a draw every ${r.interval} s counts as ${M.ROW_INTERVAL_MIN} s`);
    const si = tl().spawn_interval == null ? 0.5 : Number(tl().spawn_interval);
    if (si > 0 && M.rowDrawInterval(r, si) * 4 < si) mark(key, 'warn', `a draw every ${M.rowDrawInterval(r, si)} s is over 4× as often as the spawn check (${si} s): this row brings over 4× what its weight says`);
  }

  /** Pass 84 (lane TIMELINE; INTERFACES.md): a row's elite, special, banner, ring radius and role. An unknown modifier and a
   *  ring radius under 1 m block Save; a banner or the wave keys on a continuous row, a ring radius without a ring, an
   *  unknown role and an elite special are warnings (the game ignores or overrides them). */
  function rowKeyIssues(r, key, mark) {
    const pace = String(r.pace || 'continuous');
    if (r.elite != null && r.elite !== '' && r.elite !== 'random' && !elite(r.elite)) mark(key, 'error', `unknown elite modifier "${r.elite}"`);
    if (r.special != null && typeof r.special !== 'boolean') mark(key, 'error', 'special is on or off (true / false)');
    if (r.special === true && r.elite) mark(key, 'warn', 'special and an elite modifier: an elite-modified creature never comes as its special');
    if (r.banner != null && pace !== 'waves' && pace !== 'once') mark(key, 'warn', 'a banner shows only when a wave fires: this row is continuous');
    if (r.ring_radius != null) {
      if (!(Number(r.ring_radius) >= 1)) mark(key, 'error', 'the ring radius is at least 1 m');
      else if (r.pattern !== 'ring') mark(key, 'warn', 'a ring radius means nothing unless Pattern is Ring');
    }
    if (r.role != null && r.role !== '' && !['fodder', 'swarm', 'tank', 'ranged', 'elite', 'special'].includes(String(r.role))) mark(key, 'warn', `unknown role "${r.role}" (drawn untagged)`);
    if (r.enemy === 'roster' && !r.elite) mark(key, 'warn', 'the roster draw without an elite modifier: plain creatures drawn by Elite weight (set Elite modifier for coloured elites)');
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
      // pass 84 (INTERFACES.md): `enemy` may be "roster" (the coloured-elite draw) or a list with weights
      if (r.enemy === 'roster') {
        if (r.variant) mark(key, 'warn', 'an art variant means nothing on the roster draw (each creature comes in its own row\'s look)');
      } else if (Array.isArray(r.enemy)) {
        if (!r.enemy.length) mark(key, 'error', 'an empty list of creatures');
        for (const id of r.enemy) if (!creature(id)) mark(key, 'error', `unknown creature "${id || ''}"`);
        if (r.variant && !r.enemy.every((id) => variantOk(id, r.variant))) mark(key, 'error', `art variant "${r.variant}" is not one of every listed creature's`);
        if (r.weights_list != null && (!Array.isArray(r.weights_list) || r.weights_list.length !== r.enemy.length)) mark(key, 'warn', 'the list\'s weights do not match its creatures');
      } else if (!creature(r.enemy)) mark(key, 'error', `unknown creature "${r.enemy || ''}"`);
      else if (!variantOk(r.enemy, r.variant)) mark(key, 'error', `${U.theName(creatureName(r.enemy))} has no art variant "${r.variant}"`);
      rowKeyIssues(r, key, mark);
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
      paceIssues(r, key, mark, hard);
      intervalIssues(r, key, mark);
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
      // pass 87: a stage's boss fires at its window's end (stage_list)
      if (ev.type === 'boss' && t > 0 && !M.stageList(d).some((w) => Math.abs(w.end - t) <= 0.5)) mark(key, 'warn', `a boss away from a stage's end (${M.stageList(d).map((w) => fmtT(w.end)).join(', ')}): a stage run ends at the boss at its end`);
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
    // pass 103 (lane LE; Garry's 500 against the On screen lane's numbers): cap_max cuts the curve, so a point above it
    // changes nothing
    { const cc = capCut(); if (cc.cut) mark('cap', 'warn', `cap_max (${cc.max}) is under your cap curve (it asks for up to ${cc.raw}): the cap is ${cc.max} load wherever the curve is above it, so those points change nothing (raise cap_max in the Cap panel, or lower the points)`); }
    // pass 84: the floor curve (the least creatures alive)
    if (d.floor_curve != null) {
      const fc = d.floor_curve;
      if (!Array.isArray(fc) || fc.some((p) => !isPair(p))) mark('floor', 'error', 'a floor point is not [seconds, creatures]');
      else {
        if (!inOrder(fc)) mark('floor', 'warn', 'the floor curve is not in time order (Save sorts it)');
        if (fc.some((p) => Number(p[1]) < 0)) mark('floor', 'error', 'a negative floor');
        const hardN = Number(d.hard_cap) || Infinity;
        if (fc.some((p) => Number(p[1]) > hardN)) mark('floor', 'warn', `a floor above the hard cap (${d.hard_cap} bodies): it is never met`);
      }
    }
    validateCurve('hp', d.hp_curve, mark, 'the HP curve');
    validateCurve('dmg', d.damage_curve, mark, 'the damage curve');
    // pass 82 (lane XP): the XP growth type's checks (xp_model.js: a level needing 0 XP or less, an unknown type, ...)
    if (typeof XpModel !== 'undefined') for (const m of XpModel.issues(d)) mark('settings', m.level, `XP per level: ${m.msg}`);
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
      const SLs = s < stages() ? stageLen(s) : stageLen(stages() - 1);
      for (const v of list) if (Number(v) < 0 || Number(v) > SLs) { mark('paths', 'warn', `a path time (${v}) is outside stage ${s + 1} (0–${SLs} s)`); break; }
    });
    const sp = d.specials || {};
    for (const row of sp.pool || []) {
      const id = typeof row === 'string' ? row : row.enemy;
      if (!creature(id)) mark('specials', 'error', `unknown special "${id}"`);
    }
    for (const row of ((d.pickups || {}).roster || [])) if (!pickup(row.id)) mark('pickups', 'warn', `unknown power-up "${row.id}"`);
    if (!M.hasStageList(d) && !(Number(d.stage_length) > 0)) mark('settings', 'error', 'stage_length must be above 0');
    // pass 87 (lane STOOLS): the stage list's own checks (lengths, ids, filters, a boss at each end)
    if (typeof StageModel !== 'undefined') for (const m of StageModel.issues(d)) mark(`stage:${m.i}`, m.level, m.msg);
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
    if (Array.isArray(d.floor_curve)) sortPoints(d.floor_curve);
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
    // pass 103 (lane LE; Garry: "Stage 2 save is not working, it's just saying `Saving and importing...` and nothing is
    // happening"): the server waited up to two silent minutes for the Godot lock. Now the line counts the seconds, the
    // server queues the import after a short wait and says who holds the lock, the page follows that job to its end,
    // and whatever happens the line ends in saved / saved + import queued (the job) / failed with the reason.
    S.saving = true;
    const token = ++saveSeq;
    importWatch = null;
    const t0 = Date.now();
    const busyText = () => `Saving and importing… ${Math.round((Date.now() - t0) / 1000)} s (the import waits for the Godot lock first)`;
    status(busyText(), 'busy');
    const tick = setInterval(() => { if (S.saving && saveSeq === token) status(busyText(), 'busy'); }, 1000);
    const ctl = typeof AbortController !== 'undefined' ? new AbortController() : null;
    const limit = setTimeout(() => { if (ctl) ctl.abort(); }, SAVE_TIMEOUT_MS);
    try {
      updateTopBar();
      const r = await fetch('/api/map/' + S.mapId, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(S.map), signal: ctl ? ctl.signal : undefined });
      let res;
      try { res = await r.json(); } catch (_) { throw new Error(`HTTP ${r.status}: the server's answer was not JSON`); }
      if (!res.ok) throw new Error(res.error || `HTTP ${r.status}`);
      S.saved = JSON.stringify(S.map);
      const o = saveOutcome(res, new Date().toLocaleTimeString());
      status(o.text, o.kind, res.output);
      if (o.watch) watchImport(o.watch, o.text, token, res.lock ? { who: res.lock.who, age_s: Number(res.lock.age_s) || 0, at: Date.now() } : null);
    } catch (e) {
      const aborted = e && (e.name === 'AbortError' || /abort/i.test(String(e.message)));
      status(aborted ? `Save: no answer from the server in ${Math.round(SAVE_TIMEOUT_MS / 1000)} s; the file may be written (Revert shows what is on disk after a reload), the import did not report` : 'Save failed: ' + (e && e.message ? e.message : e), 'bad');
    } finally {
      clearInterval(tick);
      clearTimeout(limit);
      S.saving = false;
      try { render('all'); } catch (e) { console.error('render after save', e); }
    }
  }

  // pass 103 (lane LE): the server answers within SAVE_LOCK_WAIT (8 s) + the import (IMPORT_TIMEOUT, 120 s): past this the
  // page stops waiting and says so
  const SAVE_TIMEOUT_MS = 180000;
  let saveSeq = 0, importWatch = null;

  /** Pass 103 (lane LE): the status line for a map Save's answer: {text, kind, watch (the import job to follow)}. Pure. */
  function saveOutcome(res, when) {
    const where = `Saved ${res.wrote} at ${when}`;
    if (res.import_ok) return { text: `${where} · import OK · backup ${String(res.backup || '').split('/').pop()}`, kind: 'good' };
    if (res.import_ok === null || res.import_ok === undefined) {
      const lk = res.lock || null;
      const held = lk ? `the Godot lock is held by ${lk.who} for ${fmtAge(lk.age_s)}` : 'the Godot lock is busy';
      if (res.import_job) {
        return { text: `${where} · import ${res.import_joined ? 'joins the queued job' : 'queued as job'} ${res.import_job}: ${held}; it runs when the lock frees (the game plays the old .tres until then)`, kind: 'busy', watch: res.import_job };
      }
      return { text: `${where} · NOT IMPORTED: ${held} and no import job could be queued (${res.output || 'no reason given'}); the game plays the old .tres`, kind: 'bad' };
    }
    return { text: `${where} · IMPORT FAILED (the game still plays the old .tres): ${String(res.output || '').split('\n').filter(Boolean).slice(-1)[0] || 'no output'}`, kind: 'bad' };
  }

  /** Seconds as the status line says them: "45 s", "12 min", "1 h 21 min". */
  function fmtAge(s) {
    const v = Math.max(0, Math.round(Number(s) || 0));
    if (v < 120) return `${v} s`;
    if (v < 3600) return `${Math.round(v / 60)} min`;
    return `${Math.floor(v / 3600)} h ${Math.round((v % 3600) / 60)} min`;
  }

  /** Pass 103 (lane LE): what the status line says about a queued import job: {done, text, kind}. `job` the record from
   *  GET /api/job/<id> (a merged one: done with merged_into, followed by the caller). Pure. */
  function importJobLine(job, base, lk, now) {
    const st = job ? String(job.state || '') : 'gone';
    const id = job ? job.id : '?';
    if (st === 'done') return { done: true, text: `${base.split(' · import ')[0]} · import OK (job ${id} ran)`, kind: 'good' };
    if (st === 'failed' || st === 'interrupted') return { done: true, text: `${base.split(' · import ')[0]} · IMPORT FAILED in job ${id}: ${job.error || st} (the game still plays the old .tres; the Jobs tab has its log)`, kind: 'bad' };
    if (st === 'cancelled') return { done: true, text: `${base.split(' · import ')[0]} · the import job ${id} was cancelled: NOT IMPORTED (the game plays the old .tres; Save again to queue it)`, kind: 'bad' };
    if (st === 'gone') return { done: true, text: `${base.split(' · import ')[0]} · the import job is no longer in the queue (look at the Jobs tab)`, kind: 'bad' };
    const lw = job.lock_waits && typeof job.lock_waits === 'object' ? Object.entries(job.lock_waits)[0] : null;
    // the holder as the job names it; how long the lock has been held when the Save's answer named the same holder
    const age = lk && lw && String(lw[1]).startsWith(String(lk.who)) ? ` for ${fmtAge(lk.age_s + Math.max(0, ((now || Date.now()) - lk.at) / 1000))}` : '';
    const wait = lw ? `waiting for the ${lw[0] === 'godot' ? 'Godot' : lw[0]} lock, held by ${lw[1]}${age}` : st === 'running' ? 'importing now' : 'queued behind other jobs in the Godot lane';
    return { done: false, text: `${base.split(' · import ')[0]} · import job ${id}: ${wait}; the game plays the old .tres until it has run`, kind: 'busy' };
  }

  /** Pass 103 (lane LE): follow a queued import job every 3 s until it has run (a merged job is followed into the one it
   *  joined); the status line is updated while it still shows ours, else the end comes as a toast. A new Save stops it. */
  function watchImport(jobId, base, token, lk) {
    let id = jobId, mine = base, misses = 0;
    importWatch = { id, token };
    const step = async () => {
      if (saveSeq !== token || !importWatch || importWatch.token !== token) return;
      let job = null;
      try {
        const r = await fetch('/api/job/' + encodeURIComponent(id));
        if (r.ok) job = await r.json();
        else if (r.status !== 404) throw new Error(`HTTP ${r.status}`);
        misses = 0;
      } catch (_) {
        if (++misses < 20) { setTimeout(step, 3000); return; }
      }
      if (saveSeq !== token) return;
      const rec = job && job.job ? job.job : job;
      if (rec && rec.state === 'done' && rec.merged_into && rec.merged_into !== id) { id = rec.merged_into; importWatch.id = id; setTimeout(step, 500); return; }
      const line = importJobLine(rec && rec.id ? rec : null, base, lk);
      const sEl = document.getElementById('status');
      const ours = sEl && sEl.textContent === mine;
      if (ours) { status(line.text, line.kind); mine = line.text; } else if (line.done) toast(line.text);
      if (line.done) { importWatch = null; return; }
      setTimeout(step, 3000);
    };
    setTimeout(step, 1500);
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
      // pass 77 (lane SIMUI): the run sim (sim.js: its own state, polling and charts; plays the saved map)
      else if (S.tab === 'sim' && typeof Sim !== 'undefined') Sim.render(panel);
      // pass 93 (lane PREVIEW): the driver library (drivers.js: its own state; reads tools/dl/drivers, writes nothing)
      else if (S.tab === 'drivers' && typeof Drivers !== 'undefined') Drivers.render(panel);
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
    // pass 87: in a stage tab the stage run's own clock comes first ("2:10 in stage 2 · 9:20 on the map")
    const vs = viewStage();
    const own = vs != null ? `${fmtT(Math.max(0, t - stageStart(vs)))} into stage ${vs + 1} · map ` : '';
    c.textContent = `${own}${fmtT(t)} · ${stageName(stageAt(t))} · cap ${capAt(t)} load${extra ? ' · ' + extra : ''}`;
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
    route(here());   // pass 97: #<tab> (a reload comes back to it)
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
    S, init, loadMap, refreshCreatures, creature, creatureName, elite, pickup, variantOk, iconFor, playCode, creatureColor, CREATURE_COLORS,
    tl, stageLength, stages, runEnd, viewEnd, stageAt, stageName, stageMult, samplePoints, capAt, capRawAt, capCut, hellCapAt,
    // pass 87 (lane STOOLS): the stage windows and the stage tabs
    stageList, stageStart, stageEnd, stageLen, stageWindow, viewStage, viewStart, setStageView, portalSeconds,
    hpTimeMult, dmgTimeMult, hpMultAt, dmgMultAt, creatureAt, rowNumbers, eventNumbers, sourceName, actual, actualAt, knockbackOf, rowWeight, rosterAt, waveEnd, wavesAt, nextEvent,
    eventLabel, eventShares, waveAlts, snapshot, pushHistory, apply, undo, redo, dirty, selected, select, selKey, newWave,
    newRow, newRowPreset, splitRow, convertRow, newEvent, deleteSelected, duplicateSelected, moveRow, moveRowTo, shiftWeights, sortPoints, nudge, validate,
    issuesFor, save, revert, exportJson, render, status, setClock, toast, switchTab, BOSS_WINDOW,
    route, applyRoute,   // pass 97 (lane LIVE): the hash routes
    spawned, spawnOpts, setAssume, turnoverSource, setSimLife, setUseSimLife,
  };
})();
