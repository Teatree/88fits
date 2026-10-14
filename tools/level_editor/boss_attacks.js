'use strict';
// Pass 72 (lane BOSS): the Boss attacks tab. Garry: "add the ability to create custom attacks for bosses. Like colouring
// the projectile, deciding the ranges, etc. Like create custom ones that I can name and stuff". Every attack is a content
// folder (content/boss_attacks/<id>/<id>.json, game/core/data/BossAttackDef.gd); this page lists them, creates one from a
// template, names it, edits every number with its help (the grey number is the game's default), previews it from above
// to scale (the boss, the landing spots and their gaps, the hero; a time slider and Play), assigns it to any boss or
// scripted creature (their boss.attacks gets {"name": id}) and deletes it. The routes are boss_attacks_io.py; the maths
// boss_model.js. Ctrl+S saves the open attack, Ctrl+Z / Ctrl+Y step through its edits.
const BossAttacks = (() => {
  const { el, svg, clear, fmtN } = U;
  const M = BossModel;
  const S = {
    data: null, loading: false, failed: null,
    open: null, draft: null, base: null, mtime: null, history: [], future: [],
    seed: 1, t: null, playing: false, busy: false, creating: null, deleting: false, msg: null,
  };

  // ------------------------------------------------------------------ the field table (BossAttackDef's groups)

  const o = (v, label, help) => ({ v, label: label || v, help: help || '' });
  const LOOK_OPTS = [o('spike', 'spike: a barb, point first'), o('spit', 'spit: the Spit Cactus\'s ball'), o('pellet', 'pellet: a lead ball'), o('shard', 'shard: a golden sliver'), o('rock', 'rock: a stone'), o('fire', 'fire: a glowing ball')];
  const SHAPE_OPTS = [o('rings', 'rings round the centre'), o('grid', 'a hex grid'), o('spiral', 'a sunflower spiral'), o('random', 'random, kept apart')];
  const ORDER_OPTS = [o('out', 'out: nearest first'), o('in', 'in: farthest first'), o('random', 'random'), o('sweep', 'sweep: round like a clock hand')];
  const AIM_OPTS = [o('hero', 'at the hero'), o('random', 'a random way'), o('fixed', 'fixed (due east)')];
  const CENTER_OPTS = [o('boss', 'round the boss'), o('hero', 'round the hero\'s spot')];
  const TEL_OPTS = [o('circles', 'circles on the landing spots'), o('lines', 'lines down the shots\' way'), o('ring', 'a ring round its reach'), o('none', 'no warning')];
  // pass 73 (lane GROUND): a rain's landing (BossAttackDef.LANDING_MODES)
  const MODE_OPTS = [o('stagger', 'stagger: one after another, from its back'), o('volley', 'volley: one spew from its mouth, landing together')];
  const KIND_OPTS = [
    o('rain', 'rain: shots thrown up and out, landing on a pattern', 'projectiles thrown up and out in every direction, landing on the points of a pattern round the boss, each spot warned before it lands; the hero is hit only inside a landing circle'),
    o('volley', 'volley: straight shots out from the boss', 'shots flying straight out over a fan (or all round), in waves; a shot hits the hero once and is gone'),
    o('ring', 'ring: rings racing out', 'rings racing out from the boss; each hits the hero once as it passes him'),
    o('slam', 'slam: a blast round the boss', 'a blast round the boss (or the hero\'s spot) after the wind-up'),
    o('script', 'script: a built-in with your numbers', 'one of the built-in attacks (rumble, slam, roll, ...) under its own name with its own numbers'),
  ];
  const ALL = ['rain', 'volley', 'ring', 'slam'];
  const SHOTS = ['rain', 'volley'];
  const SECTIONS = [
    ['projectile', 'Projectile', 'what flies: its look, colour and size, how it flies'],
    ['pattern', 'Pattern', 'where it lands or goes: the layout, the ranges, the gap rule'],
    ['landing', 'Landing', 'the circle a rain\'s shot hurts in'],
    ['telegraph', 'Telegraph', 'how the hero is warned'],
    ['_top', 'Damage and push', 'what a hit does'],
    ['timing', 'Timing', 'wind-up, stagger, rest'],
    ['spew', 'Spew', 'a volley rain: the crouch, and the shots out of the boss\'s mouth (pass 73)'],
    ['sounds', 'Sounds', 'ids from content/sounds/soundmap.json'],
  ];
  const FIELDS = [
    { g: 'projectile', k: 'look', label: 'Shot look', type: 'select', opts: LOOK_OPTS, kinds: SHOTS, help: 'the shot\'s shape: spike = a barb flying point first (the centipede\'s), spit = the Spit Cactus\'s ball, pellet = a small lead ball, shard = a flat golden sliver, rock = a stone, fire = a glowing ball' },
    { g: 'projectile', k: 'tint', label: 'Colour', type: 'color', kinds: ALL, help: 'its colour: the body a darker shade, the colour itself glowing (a ring and a slam flash in it)' },
    { g: 'projectile', k: 'size', label: 'Size ×', type: 'number', min: 0.1, step: 0.1, kinds: SHOTS, help: 'times the look\'s size (the barb is 0.8 m long at 1)' },
    { g: 'projectile', k: 'glow', label: 'Glow', type: 'number', min: 0, max: 4, step: 0.1, kinds: SHOTS, help: 'how bright its colour glows: 0 none, 1 like the game\'s shots, 2 hot' },
    { g: 'projectile', k: 'flight', label: 'Flight (s)', type: 'number', min: 0.1, step: 0.05, kinds: ['rain'], help: 'seconds each shot is in the air, from the boss\'s back to its spot (on the creatures\' clock: ×1/pace on the map)' },
    { g: 'projectile', k: 'arc', label: 'Arc (m)', type: 'number', min: 0, step: 0.5, kinds: ['rain'], help: 'how high its arc rises over the straight line' },
    { g: 'projectile', k: 'trail', label: 'Trail', type: 'bool', kinds: ['rain'], help: 'three smaller copies follow each shot' },
    { g: 'projectile', k: 'speed', label: 'Speed (m/s)', type: 'number', min: 0.5, step: 0.5, kinds: ['volley', 'ring'], help: 'volley: how fast a shot flies; ring: how fast the ring races out on average (fast at first, slowing)' },
    { g: 'projectile', k: 'range', label: 'Range (m)', type: 'number', min: 1, step: 1, kinds: ['volley'], help: 'how far a shot flies (the warning lines are this long)' },
    { g: 'projectile', k: 'hit_radius', label: 'Hit radius (m)', type: 'number', min: 0.05, step: 0.05, kinds: ['volley'], help: 'how close a shot must pass the hero\'s middle to hit him (+0.3 m for his body)' },
    { g: 'pattern', k: 'shape', label: 'Layout', type: 'select', opts: SHAPE_OPTS, kinds: ['rain'], help: 'how the landing spots are laid out: rings round the centre, a hex grid, a sunflower spiral, or random spots kept a spacing apart' },
    { g: 'pattern', k: 'center', label: 'Centre', type: 'select', opts: CENTER_OPTS, kinds: ['rain', 'slam'], help: 'round the boss, or round the spot the hero stood on when the wind-up began' },
    { g: 'pattern', k: 'radius_min', label: 'Inner radius (m)', type: 'number', min: 0, step: 0.2, kinds: ['rain'], help: 'no spot nearer the centre than this (keep it past the boss\'s body: the Gila\'s is 2.4 m)' },
    { g: 'pattern', k: 'radius_max', label: 'Outer radius (m)', type: 'number', min: 0.5, step: 0.5, kinds: ['rain', 'ring', 'slam'], help: 'rain: the outer edge of the spots; ring: how far the ring races; slam: the blast\'s radius' },
    { g: 'pattern', k: 'spacing', label: 'Spacing (m)', type: 'number', min: 0.3, step: 0.1, kinds: ['rain'], help: 'the distance between neighbouring spots\' centres (never below 2 × the landing radius + the gap: it is raised to that)' },
    { g: 'pattern', k: 'gap', label: 'Gap (m)', type: 'number', min: 0, step: 0.1, kinds: ['rain'], help: 'THE GAP RULE: the least free sand between two neighbouring circles, edge to edge. A spot that would come closer is dropped. The hero is 0.9 m wide: 1.0 leaves him room' },
    { g: 'pattern', k: 'jitter', label: 'Jitter', type: 'number', min: 0, max: 1, step: 0.05, kinds: ['rain'], help: 'how far each spot moves at random, a share of half the spacing (it never closes a gap below the rule)' },
    { g: 'pattern', k: 'count', label: 'Count', type: 'int', min: 0, step: 1, kinds: ['rain', 'volley', 'ring'], help: 'rain: at most this many spots (0 = every spot that fits); volley: shots in each wave; ring: how many rings' },
    { g: 'pattern', k: 'turn', label: 'Turn at random', type: 'bool', kinds: ['rain'], help: 'the whole layout turned at random each time, so it never falls on the same places' },
    { g: 'pattern', k: 'order', label: 'Landing order', type: 'select', opts: ORDER_OPTS, kinds: ['rain'], help: 'which spots land first: out = the nearest first (a ripple outwards), in = the farthest first, random, sweep = round like a clock hand' },
    { g: 'pattern', k: 'spread_deg', label: 'Spread (°)', type: 'number', min: 0, max: 360, step: 5, kinds: ['volley'], help: 'the fan the shots spread over; 360 = all round' },
    { g: 'pattern', k: 'aim', label: 'Aim', type: 'select', opts: AIM_OPTS, kinds: ['volley'], help: 'the middle of the fan: at the hero (where he stood as the wind-up began), a random way, or always the same way' },
    { g: 'pattern', k: 'waves', label: 'Waves', type: 'int', min: 1, step: 1, kinds: ['volley'], help: 'how many volleys' },
    { g: 'pattern', k: 'wave_gap', label: 'Between waves (s)', type: 'number', min: 0, step: 0.05, kinds: ['volley', 'ring'], help: 'seconds between two volleys, or two rings' },
    { g: 'pattern', k: 'width', label: 'Ring width (m)', type: 'number', min: 0.1, step: 0.1, kinds: ['ring'], help: 'how thick each ring is' },
    { g: 'landing', k: 'radius', label: 'Landing radius (m)', type: 'number', min: 0.1, step: 0.05, kinds: ['rain'], help: 'the circle each shot lands in: the hero is hit only inside it (his middle within the radius + 0.2 m)' },
    { g: 'landing', k: 'mode', label: 'Landing', type: 'select', opts: MODE_OPTS, kinds: ['rain'], help: 'stagger: the shots leave the boss\'s back one after another and land over the Stagger; volley (pass 73, the Gila\'s cactus rain): the boss crouches, rears up and spews them all from its mouth, each leaving within the Spew\'s Burst and landing within the Stagger of the others, the nearest first' },
    { g: 'telegraph', k: 'kind', label: 'Warning', type: 'select', opts: TEL_OPTS, kinds: ALL, help: 'rain: a red circle on each landing spot (and the edge of the area through the wind-up); volley: a line down each shot\'s way; ring and slam: a circle round its reach; none = no warning' },
    { g: 'telegraph', k: 'color', label: 'Warning colour', type: 'color', kinds: ALL, help: 'the warning\'s colour' },
    { g: 'telegraph', k: 'seconds', label: 'Circle shows (s)', type: 'number', min: 0, step: 0.05, kinds: ['rain'], help: 'how long before a shot lands its circle shows (×1/pace on the map). The hero walks about 3 m a second: 0.9 s is time to step out of a 0.9 m circle. With All circles at once: how long before the spikes leave every circle lights up (the wind-up is made at least this long)' },
    { g: 'telegraph', k: 'all_at_once', label: 'All circles at once', type: 'bool', kinds: ['rain'], help: 'pass 73: every landing circle lights up together, Circle shows seconds before the shots leave (at the wind-up\'s start when the wind-up is no longer), full size from the start, and stays lit until its own shot lands, filling in as it comes down; off: each circle shows Circle shows seconds before its own shot lands' },
    { g: '_top', k: 'damage', label: 'Damage × bite', type: 'number', min: 0, step: 0.05, kinds: ALL, help: 'a hit takes this × the boss\'s bite (its JSON damage: the Gila\'s 24), then the stage, hero-level and map factors, as every scripted attack' },
    { g: '_top', k: 'knockback', label: 'Knockback (m/s)', type: 'number', min: 0, step: 0.5, kinds: ALL, help: 'the shove where it hits him (an evade or the Invincibility bubble ignores it)' },
    { g: '_top', k: 'lift', label: 'Lift (m/s)', type: 'number', min: 0, step: 0.5, kinds: ALL, help: 'throws him up with the shove (0 = a plain shove)' },
    { g: 'timing', k: 'windup', label: 'Wind-up (s)', type: 'number', min: 0, step: 0.05, kinds: ALL, help: 'seconds the boss winds up first, the warning showing (×1/pace on the map); a boss\'s own entry may set its own' },
    { g: 'timing', k: 'stagger', label: 'Stagger (s)', type: 'number', min: 0, step: 0.05, kinds: ['rain'], help: 'the rain arrives over this long: the first shot lands after its flight, the last this much later. A volley: every shot lands within this long of the others (the farthest a touch later)' },
    { g: 'timing', k: 'cooldown', label: 'Rest after (s)', type: 'number', min: 0, step: 0.1, kinds: ALL, help: 'the rest after this attack before the next; 0 = the boss\'s own Between attacks' },
    { g: 'timing', k: 'hold', label: 'Stands (s)', type: 'number', min: -1, step: 0.1, kinds: ALL, help: 'seconds the boss stands still after it fires; -1 = while its shots leave (the stagger, the volleys)' },
    { g: 'sounds', k: 'windup', label: 'Wind-up sound', type: 'sound', kinds: ALL, help: 'played as the wind-up starts (the boss\'s own attack sound plays anyway)' },
    { g: 'sounds', k: 'fire', label: 'Fire sound', type: 'sound', kinds: ALL, help: 'played as the shots leave (a rain: every 0.35 s while they leave)' },
    { g: 'sounds', k: 'land', label: 'Land sound', type: 'sound', kinds: ['rain'], help: 'played as shots land near the hero (at most one every 0.12 s)' },
    // pass 73 (lane GROUND; Garry: "the boss does his animation of all those projectiles flying out of his mouth but they
    // all land around the same time"): a volley rain's spew (read only with Landing = volley)
    { g: 'spew', k: 'crouch', label: 'Crouch (s)', type: 'number', min: 0, step: 0.05, kinds: ['rain'], help: 'volley: the boss crouches, squashed, through the last this many seconds of its wind-up (×1/pace on the map)' },
    { g: 'spew', k: 'squash', label: 'Crouch squash', type: 'number', min: 0.3, max: 1, step: 0.02, kinds: ['rain'], help: 'volley: how low it crouches: 1 = not at all, 0.82 = 18% shorter and a little wider' },
    { g: 'spew', k: 'stretch', label: 'Spew stretch', type: 'number', min: 1, max: 2, step: 0.05, kinds: ['rain'], help: 'volley: how tall it rears up as it spews (1.25 = a quarter taller and narrower), easing back to 1 by itself' },
    { g: 'spew', k: 'mouth', label: 'Mouth height', type: 'number', min: 0, max: 1.2, step: 0.02, kinds: ['rain'], help: 'volley: where the shots leave from, this share of the boss\'s height up its painting (the Gila\'s mouth 0.62), a little in front of it' },
    { g: 'spew', k: 'burst', label: 'Burst (s)', type: 'number', min: 0, step: 0.02, kinds: ['rain'], help: 'volley: every shot leaves the mouth within this many seconds of the spew (keep it under the Stagger)' },
  ];

  // ------------------------------------------------------------------ data

  async function getJSON(url) { const r = await fetch(url, { cache: 'no-store' }); if (!r.ok) throw new Error(`${url}: HTTP ${r.status}`); return r.json(); }
  async function postJSON(url, body) {
    const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) });
    let data; try { data = await r.json(); } catch (_) { data = { ok: false, error: `HTTP ${r.status}` }; }
    return { status: r.status, data };
  }
  function load(force) {
    if (S.loading || (S.data && !force)) return;
    S.loading = true;
    getJSON('/api/boss_attacks').then((d) => { S.data = d; S.failed = null; S.loading = false; redraw(); })
      .catch((e) => { S.failed = e.message; S.loading = false; redraw(); });
  }
  const attacks = () => (S.data && S.data.attacks) || [];
  const recOf = (id) => attacks().find((a) => a.id === id) || null;
  const scripted = () => (S.data && S.data.creatures) || [];
  const dirty = () => S.draft != null && JSON.stringify(S.draft) !== JSON.stringify(S.base);
  const redraw = () => { if (typeof App !== 'undefined' && App.S.tab === 'bossattacks') App.render('tab'); };

  /** The custom attacks as options for the Enemies tab's attack select (★ marks them). */
  function options() {
    if (!S.data) load();
    return attacks().map((a) => o(a.id, `★ ${a.name || a.id} (${a.kind})`, `a custom attack: ${a.doc || a.kind} (Boss attacks tab)`));
  }
  function get(id) { const a = recOf(id); return a ? { id: a.id, name: a.name, kind: a.kind } : null; }

  function openAttack(id) {
    if (dirty() && S.open !== id && !confirm(`Leave ${S.open} with unsaved changes?`)) return;
    const a = recOf(id);
    S.open = id;
    S.draft = a && a.json ? JSON.parse(JSON.stringify(a.json)) : null;
    S.base = S.draft ? JSON.parse(JSON.stringify(S.draft)) : null;
    S.mtime = a ? a.mtime : null;
    S.history = []; S.future = []; S.t = null; S.playing = false; S.deleting = false; S.msg = null;
    redraw();
  }
  /** From the Enemies tab's attack card: switch here with the attack open. */
  function open(id) {
    if (typeof App !== 'undefined') App.switchTab('bossattacks');
    if (S.data) openAttack(id); else { S.open = id; load(); }
  }

  function edit(fn) {
    if (!S.draft) return;
    S.history.push(JSON.stringify(S.draft));
    if (S.history.length > 200) S.history.shift();
    S.future = [];
    fn(S.draft);
    redraw();
  }
  function undo() { if (!S.history.length) return; S.future.push(JSON.stringify(S.draft)); S.draft = JSON.parse(S.history.pop()); redraw(); }
  function redo() { if (!S.future.length) return; S.history.push(JSON.stringify(S.draft)); S.draft = JSON.parse(S.future.pop()); redraw(); }
  function setVal(g, k, v) {
    edit((d) => {
      if (g === '_top') { if (v == null || v === '') delete d[k]; else d[k] = v; return; }
      if (d[g] == null || typeof d[g] !== 'object') d[g] = {};
      if (v == null || v === '') delete d[g][k]; else d[g][k] = v;
    });
  }

  async function save() {
    if (!S.draft || S.busy) return;
    const iss = M.issues(S.draft);
    if (iss.errors.length) { App.status(`Cannot save ${S.open}: ${iss.errors.join(' · ')}`, 'bad'); return; }
    if (!dirty()) { App.status('Nothing to save'); return; }
    S.busy = true; redraw();
    App.status(`Saving ${S.open} and importing…`, 'busy');
    const r = await postJSON(`/api/boss_attacks/${S.open}/save`, { json: S.draft, base_mtime: S.mtime });
    S.busy = false;
    if (r.status === 409) {
      App.status(`${S.open} changed on disk since it was opened: Reload to take the file, or Save again to keep yours`, 'bad');
      S.mtime = r.data.mtime;
      S.msg = { kind: 'conflict', text: 'The file changed on disk (Garry, or another editor). Save again keeps yours over it; Reload takes the file.' };
      redraw(); return;
    }
    if (!r.data.ok) { App.status(`Save failed: ${r.data.error}`, 'bad'); redraw(); return; }
    S.base = JSON.parse(JSON.stringify(S.draft));
    S.mtime = r.data.mtime;
    S.msg = null;
    App.status(r.data.import_ok ? `Saved ${S.open} · import OK` : `Saved ${S.open} · IMPORT NOT RUN (the game plays the old .tres until an import)`, r.data.import_ok ? 'good' : 'bad', r.data.output);
    const keep = S.open;
    S.data = null; load(true);
    S.open = keep;
  }
  function revert() { if (!S.draft || !dirty()) return; S.history.push(JSON.stringify(S.draft)); S.draft = JSON.parse(JSON.stringify(S.base)); redraw(); }
  async function reload() { const keep = S.open; S.data = null; S.loading = false; await getJSON('/api/boss_attacks').then((d) => { S.data = d; }); S.open = null; S.draft = null; S.base = null; openAttack(keep); }

  async function create(id, name, from) {
    if (dirty() && !confirm(`Leave ${S.open} with unsaved changes?`)) return;
    const body = { id, name };
    if (from.startsWith('kind:')) body.kind = from.slice(5); else body.template = from;
    const r = await postJSON('/api/boss_attacks/new', body);
    if (!r.data.ok) { S.creating.error = r.data.error; redraw(); return; }
    S.creating = null;
    App.status(`Made ${id}${r.data.import_ok ? ' · import OK' : ' · import not run'}`, r.data.import_ok ? 'good' : 'bad', r.data.output);
    S.data = await getJSON('/api/boss_attacks');
    S.open = null; S.draft = null; S.base = null;
    openAttack(id);
  }
  async function assign(cid, on) {
    if (dirty()) { App.status('Save the attack first: the boss plays the saved file', 'bad'); return; }
    S.busy = true; redraw();
    const r = await postJSON(`/api/boss_attacks/${S.open}/assign`, { creature: cid, on });
    S.busy = false;
    if (!r.data.ok) { App.status(`Could not ${on ? 'add it to' : 'take it out of'} ${cid}: ${r.data.error}`, 'bad'); redraw(); return; }
    App.status(`${on ? 'Added to' : 'Taken out of'} ${cid}'s script (${r.data.attacks.join(', ')})${r.data.import_ok ? ' · import OK' : ' · import not run'}`, r.data.import_ok ? 'good' : 'bad', r.data.output);
    S.data = await getJSON('/api/boss_attacks');
    if (typeof App !== 'undefined' && App.refreshCreatures) App.refreshCreatures();
    redraw();
  }
  async function del(cascade) {
    const r = await postJSON(`/api/boss_attacks/${S.open}/delete`, { cascade });
    if (!r.data.ok) { App.status(`Could not delete ${S.open}: ${r.data.error}`, 'bad'); return; }
    App.status(`Deleted ${S.open} (moved to ${r.data.moved_to})${r.data.left && r.data.left.length ? ' · taken out of ' + r.data.left.join(', ') : ''}`, 'good');
    S.open = null; S.draft = null; S.base = null; S.deleting = false;
    S.data = await getJSON('/api/boss_attacks');
    if (typeof App !== 'undefined' && App.refreshCreatures) App.refreshCreatures();
    redraw();
  }

  // ------------------------------------------------------------------ the page

  function render(panel) {
    const scroll = panel.scrollTop;
    const active = panel.contains(document.activeElement) ? document.activeElement.dataset.path : null;
    clear(panel);
    load();
    const page = el('div', { class: 'batk' });
    page.appendChild(el('p', { class: 'lead', html: 'A boss\'s script is a list of attacks (Enemies tab → the boss → <i>Attack script</i>). Besides the 14 built-in ones, <b>custom attacks</b> made here need no code: a <b>rain</b> of shots landing on a pattern, a <b>volley</b>, racing <b>rings</b>, a <b>slam</b>, or a built-in under its own name with its own numbers (<b>script</b>). Make one, name it, tune it with the preview, tick the bosses that use it, Save (Ctrl+S): the file is written and imported, the next run plays it.' }));
    if (S.failed) { page.appendChild(el('p', { class: 'ferr bad', text: `Could not read /api/boss_attacks: ${S.failed} (restart the editor: the route is new in pass 72)` })); panel.appendChild(page); return; }
    if (!S.data) { page.appendChild(el('p', { class: 'muted', text: 'Loading the attacks…' })); panel.appendChild(page); return; }
    if (S.open && !S.draft && recOf(S.open)) { const id = S.open; S.open = null; openAttack(id); return; }
    const grid = el('div', { class: 'batk-grid' });
    grid.appendChild(listPane());
    grid.appendChild(S.draft ? editorPane() : el('div', { class: 'batk-empty muted' }, el('p', { text: 'Pick an attack on the left, or make a new one.' })));
    page.appendChild(grid);
    panel.appendChild(page);
    panel.scrollTop = scroll;
    if (active) { const again = panel.querySelector(`[data-path="${CSS.escape(active)}"]`); if (again) again.focus({ preventScroll: true }); }
  }

  function listPane() {
    const pane = el('aside', { class: 'batk-list' });
    pane.appendChild(el('div', { class: 'batk-list-head' }, el('h2', { text: 'Custom attacks' }), el('button', { class: 'btn small primary', type: 'button', text: '+ New attack', onclick: () => { S.creating = { id: '', name: '', from: 'kind:rain', error: '' }; redraw(); } })));
    if (S.creating) pane.appendChild(createForm());
    for (const a of attacks()) {
      const users = (a.used_by || []).map((cid) => (scripted().find((c) => c.id === cid) || { name: cid }).name);
      const row = el('button', { class: 'batk-item' + (a.id === S.open ? ' on' : ''), type: 'button', onclick: () => openAttack(a.id) },
        el('span', { class: 'batk-swatch', style: `background:${(a.json && a.json.projectile && a.json.projectile.tint) || M.DEFAULTS.projectile.tint}` }),
        el('span', { class: 'batk-item-main' },
          el('span', { class: 'batk-item-name', text: a.name || a.id }),
          el('span', { class: 'batk-item-sub', text: `${a.id} · ${a.kind}${users.length ? ' · ' + users.join(', ') : ' · in no script'}` })),
        a.id === S.open && dirty() ? el('span', { class: 'dirty-dot', text: '●', title: 'unsaved changes' }) : null);
      pane.appendChild(row);
    }
    if (!attacks().length) pane.appendChild(el('p', { class: 'muted small', text: 'None yet.' }));
    const bi = el('details', { class: 'batk-builtins' }, el('summary', { text: `The ${(S.data.builtins || []).length} built-in attacks` }));
    const AF = typeof AFIELDS !== 'undefined' ? AFIELDS : null;
    for (const n of S.data.builtins || []) bi.appendChild(el('div', { class: 'small' }, el('code', { text: n }), el('span', { class: 'muted', text: ' ' + (AF && AF.ATTACKS[n] ? AF.ATTACKS[n].help : '') })));
    bi.appendChild(el('p', { class: 'muted small', text: 'A built-in is put in a script on the Enemies tab; a "script" attack here is a built-in under its own name with its own numbers.' }));
    pane.appendChild(bi);
    return pane;
  }

  function createForm() {
    const c = S.creating;
    const box = el('div', { class: 'batk-new' });
    const idIn = el('input', { type: 'text', class: 'txt', placeholder: 'id: fire_ring', value: c.id, 'data-path': 'new.id' });
    const nameIn = el('input', { type: 'text', class: 'txt', placeholder: 'Name: Ring of Fire', value: c.name, 'data-path': 'new.name' });
    idIn.addEventListener('input', () => { c.id = idIn.value.trim().toLowerCase(); });
    nameIn.addEventListener('input', () => { c.name = nameIn.value; if (!c.idTouched) { c.id = nameIn.value.trim().toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, ''); idIn.value = c.id; } });
    idIn.addEventListener('change', () => { c.idTouched = true; });
    const opts = [{ group: 'A blank one', options: KIND_OPTS.map((k) => o('kind:' + k.v, k.label, k.help)) }];
    if (attacks().length) opts.push({ group: 'A copy of', options: attacks().map((a) => o(a.id, `${a.name} (${a.id})`)) });
    const from = Forms.select(opts, c.from, (v) => { c.from = v || 'kind:rain'; }, { path: 'new.from' });
    box.appendChild(el('div', { class: 'frow' }, el('label', { class: 'flabel', text: 'Name' }), el('div', { class: 'fctl' }, nameIn)));
    box.appendChild(el('div', { class: 'frow' }, el('label', { class: 'flabel', text: 'Id', title: 'lower-case letters, digits and _: the file\'s and the scripts\' name for it' }), el('div', { class: 'fctl' }, idIn)));
    box.appendChild(el('div', { class: 'frow' }, el('label', { class: 'flabel', text: 'Start from' }), el('div', { class: 'fctl' }, from)));
    if (c.error) box.appendChild(el('div', { class: 'ferr bad', text: c.error }));
    box.appendChild(el('div', { class: 'alt-actions' },
      el('button', { class: 'btn small primary', type: 'button', text: 'Make it', onclick: () => {
        const id = (c.id || '').trim();
        if (!/^[a-z][a-z0-9_]*$/.test(id)) { c.error = 'the id is lower-case letters, digits and _, starting with a letter'; redraw(); return; }
        if (M.SCRIPTS.includes(id)) { c.error = `"${id}" is a built-in attack's name`; redraw(); return; }
        create(id, c.name || id, c.from);
      } }),
      el('button', { class: 'btn small ghost', type: 'button', text: 'Cancel', onclick: () => { S.creating = null; redraw(); } })));
    return box;
  }

  function editorPane() {
    const d = S.draft;
    const kind = M.KINDS.includes(d.kind) ? d.kind : 'rain';
    const iss = M.issues(d);
    const pane = el('section', { class: 'batk-edit' });
    // the head: name, id, kind, the buttons
    const nameIn = Forms.textInput({ key: 'name' }, d.name, (v) => edit((x) => { x.name = v || ''; }), { path: 'name', placeholder: 'a name' });
    nameIn.classList.add('batk-name');
    pane.appendChild(el('div', { class: 'batk-head' },
      nameIn,
      el('code', { class: 'batk-id', text: S.open }),
      Forms.select(KIND_OPTS, kind, (v) => edit((x) => changeKind(x, v || 'rain')), { path: 'kind' }),
      el('span', { class: 'spacer' }),
      el('button', { class: 'btn small', type: 'button', text: 'Undo', disabled: !S.history.length, onclick: undo }),
      el('button', { class: 'btn small', type: 'button', text: 'Revert', disabled: !dirty(), onclick: revert }),
      el('button', { class: 'btn small primary' + (iss.errors.length && dirty() ? ' blocked' : ''), type: 'button', text: S.busy ? 'Saving…' : 'Save attack', disabled: !dirty() || S.busy, title: iss.errors.length ? iss.errors.join(' · ') : 'write the JSON and import it (Ctrl+S)', onclick: save }),
      el('button', { class: 'btn small danger', type: 'button', text: 'Delete…', onclick: () => { S.deleting = !S.deleting; redraw(); } })));
    if (S.msg) pane.appendChild(el('div', { class: 'ferr warn' }, el('span', { text: S.msg.text + ' ' }), el('button', { class: 'btn small', type: 'button', text: 'Reload', onclick: reload })));
    if (S.deleting) {
      const rec = recOf(S.open) || {};
      const users = rec.used_by || [];
      pane.appendChild(el('div', { class: 'batk-confirm' },
        el('span', { text: users.length ? `Delete ${S.open}? It is in the script of ${users.join(', ')}: deleting takes it out of those first. The folder goes to the editor's backups.` : `Delete ${S.open}? The folder goes to the editor's backups.` }),
        el('button', { class: 'btn small danger', type: 'button', text: 'Delete', onclick: () => del(true) }),
        el('button', { class: 'btn small ghost', type: 'button', text: 'Cancel', onclick: () => { S.deleting = false; redraw(); } })));
    }
    const doc = Forms.textareaInput({ key: 'doc' }, d.doc, (v) => edit((x) => { x.doc = v || ''; }), { path: 'doc', placeholder: 'what it is, in a line or two (the list and the Enemies tab show it)' });
    pane.appendChild(el('div', { class: 'frow' }, el('label', { class: 'flabel', text: 'What it is' }), el('div', { class: 'fctl' }, doc)));
    // issues
    if (iss.errors.length || iss.warnings.length) {
      const box = el('div', { class: 'batk-issues' });
      for (const e of iss.errors) box.appendChild(el('div', { class: 'ferr bad', text: e }));
      for (const w of iss.warnings) box.appendChild(el('div', { class: 'ferr warn', text: w }));
      pane.appendChild(box);
    }
    pane.appendChild(usedBy());
    if (kind === 'script') { pane.appendChild(scriptPane(d)); return pane; }
    pane.appendChild(preview(d, kind));
    for (const [g, title, sub] of SECTIONS) {
      const rows = FIELDS.filter((f) => f.g === g && f.kinds.includes(kind));
      if (!rows.length) continue;
      const det = el('details', { class: 'asection batk-sec', open: true }, el('summary', {}, el('span', { class: 'asec-title', text: title }), el('span', { class: 'muted small', text: ' ' + sub })));
      const body = el('div', { class: 'asec-body' });
      for (const f of rows) body.appendChild(fieldRow(d, f));
      det.appendChild(body);
      pane.appendChild(det);
    }
    return pane;
  }

  /** A new kind keeps every number the two kinds share; the rows only the new kind reads take its blank's numbers (a
   *  rain's count 0 = "every spot" would be one shot a volley), and the warning becomes the new kind's usual one. */
  function changeKind(x, v) {
    const b = M.blank(v, x.id, x.name);
    const reads = (k) => new Set(FIELDS.filter((f) => f.kinds.includes(k)).map((f) => f.g + '.' + f.k));
    const had = reads(M.KINDS.includes(x.kind) ? x.kind : 'rain'), now = reads(v);
    for (const g of ['projectile', 'pattern', 'landing', 'telegraph', 'timing', 'sounds', 'spew']) if (b[g] && (x[g] == null || typeof x[g] !== 'object')) x[g] = {};
    for (const f of FIELDS) {
      const key = f.g + '.' + f.k;
      if (!now.has(key) || f.g === '_top' || !b[f.g]) continue;
      const fresh = !had.has(key) || key === 'pattern.count' || key === 'telegraph.kind';
      if (fresh && b[f.g][f.k] !== undefined) x[f.g][f.k] = b[f.g][f.k];
    }
    if (v === 'script' && !x.script) { x.script = b.script; x.params = b.params; }
    if (v === 'rain' && !x.landing) x.landing = b.landing;
    x.kind = v;
  }

  function usedBy() {
    const rec = recOf(S.open) || { used_by: [] };
    const box = el('div', { class: 'batk-used' }, el('span', { class: 'flabel', text: 'In the script of', title: 'tick a boss to add {"name": "' + S.open + '"} to its boss.attacks (the end of its cycle); untick to take it out. Written to its JSON and imported at once. The Enemies tab shows the script and orders it' }));
    const bosses = scripted().filter((c) => c.kind === 'boss');
    const others = scripted().filter((c) => c.kind !== 'boss');
    const chip = (c) => {
      const on = (rec.used_by || []).includes(c.id);
      return el('button', { class: 'batk-chip' + (on ? ' on' : ''), type: 'button', disabled: S.busy || (dirty() && !on), title: on ? `${c.name}'s script: ${c.attacks.join(' → ')} (click to take it out)` : `add it to ${c.name}'s script (${c.attacks.join(' → ') || 'empty'})`, text: `${on ? '✓ ' : '+ '}${c.name}`, onclick: () => assign(c.id, !on) });
    };
    const wrap = el('span', { class: 'batk-chips' });
    for (const c of bosses) wrap.appendChild(chip(c));
    if (others.length) {
      const more = el('details', { class: 'batk-more' }, el('summary', { text: `${others.length} more scripted creatures` }));
      for (const c of others) more.appendChild(chip(c));
      wrap.appendChild(more);
    }
    box.appendChild(wrap);
    if (dirty()) box.appendChild(el('span', { class: 'muted small', text: ' (save first: a boss plays the saved file)' }));
    return box;
  }

  function fieldRow(d, f) {
    const cur = f.g === '_top' ? d[f.k] : (d[f.g] && typeof d[f.g] === 'object' ? d[f.g][f.k] : undefined);
    const dflt = f.g === '_top' ? M.TOP_DEFAULTS[f.k] : M.DEFAULTS[f.g][f.k];
    const path = `${f.g}.${f.k}`;
    const set = (v) => setVal(f.g, f.k, v);
    let ctl;
    if (f.type === 'select') ctl = Forms.select(f.opts, cur == null ? '' : cur, set, { path, emptyLabel: `— (${dflt})` });
    else if (f.type === 'bool') ctl = Forms.bool3Input({ key: path }, cur, set, { path, placeholder: dflt ? 'yes' : 'no' });
    else if (f.type === 'color') ctl = colorInput(cur, dflt, set, path);
    else if (f.type === 'sound') {
      const sounds = (S.data && S.data.sounds) || [];
      ctl = Forms.select(sounds.map((x) => o(x)), cur == null ? '' : cur, set, { path, emptyLabel: dflt ? `— (${dflt})` : '— none' });
    } else ctl = Forms.numberInput({ key: path, min: f.min, max: f.max, step: f.step, int: f.type === 'int' }, cur, set, { path, placeholder: dflt, cls: 'short' });
    return Forms.row({ key: path, label: f.label, help: f.help }, ctl, {});
  }

  function colorInput(cur, dflt, set, path) {
    const v = cur || dflt || '#ffffff';
    const pick = el('input', { type: 'color', value: /^#[0-9a-fA-F]{6}$/.test(v) ? v : '#ffffff', 'data-path': path + '.pick' });
    const txt = el('input', { type: 'text', class: 'txt short', value: cur || '', placeholder: dflt || '', 'data-path': path });
    pick.addEventListener('change', () => set(pick.value.toUpperCase()));
    txt.addEventListener('change', () => { const t = txt.value.trim(); set(t === '' ? null : (t.startsWith('#') ? t : '#' + t).toUpperCase()); });
    return el('span', { class: 'batk-color' }, pick, txt);
  }

  function scriptPane(d) {
    const box = el('details', { class: 'asection batk-sec', open: true }, el('summary', {}, el('span', { class: 'asec-title', text: 'The built-in it plays' })));
    const body = el('div', { class: 'asec-body' });
    const AF = typeof AFIELDS !== 'undefined' ? AFIELDS : null;
    body.appendChild(Forms.row({ key: 'script', label: 'Built-in', help: 'the built-in attack this one plays, under this attack\'s name, with the keys below' },
      Forms.select(M.SCRIPTS.map((n) => o(n, AF && AF.ATTACKS[n] ? `${n}: ${AF.ATTACKS[n].label}` : n, AF && AF.ATTACKS[n] ? AF.ATTACKS[n].help : '')), d.script || '', (v) => edit((x) => { x.script = v || 'slam'; }), { path: 'script' })));
    const ta = Forms.textareaInput({ key: 'params' }, JSON.stringify(d.params || {}, null, 1), (v) => {
      let p; try { p = JSON.parse(v || '{}'); } catch (e) { App.status(`params: not JSON (${e.message})`, 'bad'); return; }
      edit((x) => { x.params = p; });
    }, { path: 'params', rows: 6 });
    body.appendChild(Forms.row({ key: 'params', label: 'Its keys (JSON)', help: 'the built-in\'s own keys, as the Enemies tab\'s attack card lists them (windup, telegraph, damage, radius, ...)' }, ta));
    const spec = AF && AF.ATTACKS[d.script];
    if (spec) body.appendChild(el('p', { class: 'muted small', text: `${d.script} reads: windup, telegraph (usual: ${spec.telegraph}), reach, min_range, max_range, ` + spec.keys.map((k) => `${k.key} (${k.def == null ? '—' : k.def})`).join(', ') }));
    box.appendChild(body);
    return box;
  }

  // ------------------------------------------------------------------ the preview

  /** The attack from above, to scale, at time S.t (seconds after the wind-up begins): the boss, the hero 8 m off, the
   *  warning, the spots and the shots as they would be then. Play runs the clock; New layout throws another random. */
  function preview(d, kind) {
    const wrap = el('div', { class: 'batk-prev' });
    const boss = scripted().find((c) => (recOf(S.open) || { used_by: [] }).used_by.includes(c.id)) || scripted().find((c) => c.kind === 'boss') || { radius: 2.4, damage: 24, name: 'boss' };
    const bossR = M.num(boss.radius, 2.4);
    // (pass 73: a rain lit all at once winds up at least as long as its circles show)
    const wind = M.windupSeconds(d);
    const lay = kind === 'rain' ? M.rainLayout(d, S.seed) : null;
    const pat = M.patternFull(d);
    const rmax = M.num(pat.radius_max, 16);
    let dur = wind + 1;
    if (kind === 'rain') dur = wind + lay.lasts + 0.6;
    if (kind === 'volley') dur = wind + Math.max(M.num(pat.waves, 1) - 1, 0) * M.num(pat.wave_gap, 0.5) + M.num(M.val(d, 'projectile', 'range'), 18) / Math.max(M.num(M.val(d, 'projectile', 'speed'), 12), 0.1) + 0.3;
    if (kind === 'ring') dur = wind + Math.max(M.num(pat.count, 1) - 1, 0) * M.num(pat.wave_gap, 0.5) + rmax / Math.max(M.num(M.val(d, 'projectile', 'speed'), 12), 0.1) + 0.3;
    if (kind === 'slam') dur = wind + 0.8;
    if (S.t == null || S.t > dur) S.t = dur * 0.62;
    const t = S.t;
    const extent = Math.max(kind === 'volley' ? M.num(M.val(d, 'projectile', 'range'), 18) : rmax, 10) + 2;
    const W = 460, C = W / 2, ppm = (W / 2 - 8) / extent;
    const X = (x) => C + x * ppm, Y = (z) => C + z * ppm;
    const s = svg('svg', { class: 'batk-svg', viewBox: `0 0 ${W} ${W}`, width: W, height: W, role: 'img', 'aria-label': 'the attack from above' });
    s.appendChild(svg('rect', { x: 0, y: 0, width: W, height: W, rx: 10, class: 'bp-ground' }));
    const tint = M.val(d, 'projectile', 'tint') || '#D0242F';
    const warn = M.val(d, 'telegraph', 'color') || '#ED4A5C';
    const telKind = M.val(d, 'telegraph', 'kind');
    const heroAt = [0, -8];
    const centerHero = pat.center === 'hero';
    const cx = centerHero ? heroAt[0] : 0, cz = centerHero ? heroAt[1] : 0;
    const fired = t >= wind;
    const tc = t - wind;   // seconds after it fires
    if (kind === 'rain') {
      s.appendChild(svg('circle', { cx: X(cx), cy: Y(cz), r: lay.rmax * ppm, class: 'bp-edge' }));
      if (lay.rmin > 0) s.appendChild(svg('circle', { cx: X(cx), cy: Y(cz), r: lay.rmin * ppm, class: 'bp-edge inner' }));
      // pass 73: a rain lit all at once shows its circles instead of the area's outline
      const allAt = M.litAtOnce(d);
      if (!fired && telKind !== 'none' && !allAt) s.appendChild(svg('circle', { cx: X(cx), cy: Y(cz), r: lay.rmax * ppm, fill: 'none', stroke: warn, 'stroke-width': 2, opacity: 0.7 }));
      const tel = M.num(M.val(d, 'telegraph', 'seconds'), 0.9);
      // the narrowest gap
      let pair = null, best = Infinity;
      lay.pts.forEach((p, a) => { for (let b = a + 1; b < lay.pts.length; b++) { const q = lay.pts[b]; const g = Math.hypot(p[0] - q[0], p[1] - q[1]); if (g < best) { best = g; pair = [p, q]; } } });
      lay.pts.forEach((p, k) => {
        const land = lay.times[k];
        const x = X(cx + p[0]), y = Y(cz + p[1]), r = lay.landR * ppm;
        // when its circle lights, in seconds after the spikes leave (pass 73: all at once, before the spew)
        const litAt = allAt ? -Math.min(tel, wind) : land - tel;
        if (telKind === 'none' || tc < litAt) { s.appendChild(svg('circle', { cx: x, cy: y, r, class: 'bp-spot' })); }
        else if (tc < land) {
          const f = Math.min(Math.max((tc - litAt) / Math.max(land - litAt, 0.01), 0), 1);
          if (allAt) s.appendChild(svg('circle', { cx: x, cy: y, r, fill: warn, 'fill-opacity': 0.2 + 0.25 * f, stroke: warn, 'stroke-width': 1.8 }));
          else s.appendChild(svg('circle', { cx: x, cy: y, r: r * (0.4 + 0.6 * f), fill: warn, 'fill-opacity': 0.18, stroke: warn, 'stroke-width': 1.6 }));
        } else {
          const age = tc - land;
          s.appendChild(svg('circle', { cx: x, cy: y, r, fill: tint, 'fill-opacity': Math.max(0.15, 0.6 - age * 0.5), stroke: tint, 'stroke-width': 1 }));
        }
        // a shot in the air (from above: on the straight line from the boss; pass 73: a volley's own flight)
        const fl = lay.flights ? lay.flights[k] : lay.flight;
        const launch = land - fl;
        if (fired && tc >= launch && tc < land) {
          const u = (tc - launch) / fl;
          s.appendChild(svg('circle', { cx: X(p[0] * u + cx * u), cy: Y(p[1] * u + cz * u), r: Math.max(2.5, 0.25 * M.num(M.val(d, 'projectile', 'size'), 1) * ppm), fill: tint, stroke: '#000', 'stroke-width': 0.6 }));
        }
      });
      if (pair) {
        const [p, q] = pair;
        const len = Math.hypot(q[0] - p[0], q[1] - p[1]) || 1;
        const ux = (q[0] - p[0]) / len, uz = (q[1] - p[1]) / len;
        s.appendChild(svg('line', { x1: X(cx + p[0] + ux * lay.landR), y1: Y(cz + p[1] + uz * lay.landR), x2: X(cx + q[0] - ux * lay.landR), y2: Y(cz + q[1] - uz * lay.landR), class: 'bp-gap' }));
      }
    } else if (kind === 'volley') {
      const aimA = pat.aim === 'fixed' ? 0 : Math.atan2(heroAt[1], heroAt[0]);
      const dirs = M.volleyDirs(d, aimA);
      const range = M.num(M.val(d, 'projectile', 'range'), 18), spd = M.num(M.val(d, 'projectile', 'speed'), 12);
      for (const a of dirs) s.appendChild(svg('line', { x1: X(0), y1: Y(0), x2: X(Math.cos(a) * range), y2: Y(Math.sin(a) * range), stroke: warn, 'stroke-width': fired ? 1 : 2.5, opacity: fired ? 0.35 : 0.85, 'stroke-linecap': 'round' }));
      if (fired) for (let w = 0; w < Math.max(Math.round(M.num(pat.waves, 1)), 1); w++) {
        const tw = tc - w * M.num(pat.wave_gap, 0.5);
        if (tw < 0 || tw * spd > range) continue;
        for (const a of dirs) s.appendChild(svg('circle', { cx: X(Math.cos(a) * tw * spd), cy: Y(Math.sin(a) * tw * spd), r: Math.max(3, 0.3 * M.num(M.val(d, 'projectile', 'size'), 1) * ppm), fill: tint }));
      }
    } else if (kind === 'ring') {
      const spd = M.num(M.val(d, 'projectile', 'speed'), 12);
      const dr = rmax / Math.max(spd, 0.1);
      const width = M.num(pat.width, 1.2);
      s.appendChild(svg('circle', { cx: X(0), cy: Y(0), r: rmax * ppm, fill: 'none', stroke: warn, 'stroke-width': fired ? 1 : 2.5, opacity: fired ? 0.3 : 0.85 }));
      if (fired) for (let w = 0; w < Math.max(Math.round(M.num(pat.count, 1)), 1); w++) {
        const f = (tc - w * M.num(pat.wave_gap, 0.5)) / dr;
        if (f < 0 || f >= 1) continue;
        const front = M.ringFront(rmax, f);
        s.appendChild(svg('circle', { cx: X(0), cy: Y(0), r: Math.max(0.5, front - front * width / rmax / 2) * ppm, fill: 'none', stroke: tint, 'stroke-width': Math.max(2, front * width / rmax * ppm), opacity: 0.85 * (1 - f * f) + 0.15 }));
      }
    } else if (kind === 'slam') {
      const r = rmax * ppm;
      if (!fired) s.appendChild(svg('circle', { cx: X(cx), cy: Y(cz), r: r * (0.4 + 0.6 * Math.min(t / Math.max(wind, 0.01), 1)), fill: warn, 'fill-opacity': 0.2, stroke: warn, 'stroke-width': 2 }));
      else if (tc < 0.6) s.appendChild(svg('circle', { cx: X(cx), cy: Y(cz), r, fill: tint, 'fill-opacity': 0.5 * (1 - tc / 0.6), stroke: tint, 'stroke-width': 2 }));
    }
    // the boss, the hero to scale, a 5 m bar
    s.appendChild(svg('circle', { cx: X(0), cy: Y(0), r: bossR * ppm, class: 'bp-boss' }));
    s.appendChild(svg('text', { x: X(0), y: Y(0) + 4, class: 'bp-label mid', text: boss.name || 'boss' }));
    s.appendChild(svg('circle', { cx: X(heroAt[0]), cy: Y(heroAt[1]), r: Math.max(2.5, M.HERO_RADIUS * ppm), class: 'bp-hero' }));
    s.appendChild(svg('text', { x: X(heroAt[0]) + 8, y: Y(heroAt[1]) + 4, class: 'bp-label', text: 'hero (to scale)' }));
    s.appendChild(svg('line', { x1: 12, y1: W - 14, x2: 12 + 5 * ppm, y2: W - 14, class: 'bp-bar' }));
    s.appendChild(svg('text', { x: 12, y: W - 19, class: 'bp-label', text: '5 m' }));
    s.appendChild(svg('text', { x: W - 10, y: 18, class: 'bp-label end', text: fired ? `${fmtN(tc, 2)} s after it fires` : `wind-up ${fmtN(t, 2)} / ${fmtN(wind, 2)} s` }));
    wrap.appendChild(s);
    // the controls and the numbers
    const side = el('div', { class: 'batk-prev-side' });
    const slider = el('input', { type: 'range', min: 0, max: dur, step: 0.01, value: t, 'data-path': 'preview.t' });
    slider.addEventListener('input', () => { S.t = Number(slider.value); S.playing = false; redraw(); });
    const play = el('button', { class: 'btn small', type: 'button', text: S.playing ? 'Pause' : '▶ Play', onclick: () => { if (S.playing) { S.playing = false; redraw(); return; } S.playing = true; if (S.t >= dur - 0.02) S.t = 0; tick(dur); } });
    side.appendChild(el('div', { class: 'batk-prev-ctl' }, play, slider, kind === 'rain' ? el('button', { class: 'btn small', type: 'button', text: 'New layout', title: 'the game turns and jitters the layout at random every time: another example', onclick: () => { S.seed = (S.seed * 7919 + 13) % 100003; redraw(); } }) : null));
    const facts = el('ul', { class: 'batk-facts small' });
    const bite = M.num(boss.damage, 24);
    const li = (h) => { const x = el('li'); x.innerHTML = h; facts.appendChild(x); };
    if (kind === 'rain') {
      li(`<b>${lay.pts.length}</b> landing spots between ${fmtN(lay.rmin, 1)} and ${fmtN(lay.rmax, 1)} m (${pat.shape}, ${pat.order === 'out' ? 'nearest first' : pat.order})`);
      li(`the narrowest gap <b>${isFinite(lay.gap) ? fmtN(lay.gap, 2) : '—'} m</b> between two circles (the rule: at least ${fmtN(M.num(pat.gap, 1), 2)} m; the hero is ${fmtN(2 * M.HERO_RADIUS, 1)} m wide) <span class="bp-gapkey">━</span>`);
      li(`the circles cover <b>${fmtN(lay.cover * 100, 0)}%</b> of the ring`);
      if (M.isVolley(d)) li(`one spew from its mouth after the ${fmtN(wind, 2)} s wind-up (it crouches the last ${fmtN(M.num(M.val(d, 'spew', 'crouch'), 0.35), 2)} s): every shot lands between ${fmtN(lay.first, 2)} s and ${fmtN(lay.lasts, 2)} s after it, <b>all within ${fmtN(lay.lasts - lay.first, 2)} s</b> (×1/pace on the map)`);
      else li(`after the ${fmtN(wind, 2)} s wind-up the shots land from ${fmtN(lay.flight, 2)} s to ${fmtN(lay.lasts, 2)} s, each circle showing ${fmtN(M.num(M.val(d, 'telegraph', 'seconds'), 0.9), 2)} s before (×1/pace on the map)`);
      if (M.litAtOnce(d)) li(`<b>every circle lights at once</b> ${fmtN(Math.min(M.num(M.val(d, 'telegraph', 'seconds'), 0.9), wind), 2)} s before the spikes leave and stays lit until its own spike lands`);
    }
    if (kind === 'volley') li(`${Math.max(Math.round(M.num(pat.count, 1)), 1)} shots a wave × ${Math.max(Math.round(M.num(pat.waves, 1)), 1)} over ${fmtN(M.num(pat.spread_deg, 360), 0)}°, ${fmtN(M.num(M.val(d, 'projectile', 'range'), 18), 0)} m at ${fmtN(M.num(M.val(d, 'projectile', 'speed'), 12), 1)} m/s`);
    if (kind === 'ring') li(`${Math.max(Math.round(M.num(pat.count, 1)), 1)} ring(s) to ${fmtN(rmax, 1)} m, ${fmtN(M.num(pat.width, 1.2), 1)} m thick`);
    if (kind === 'slam') li(`a blast of ${fmtN(rmax, 1)} m round the ${pat.center === 'hero' ? 'hero\'s spot' : 'boss'}`);
    li(`a hit: ${fmtN(M.topVal(d, 'damage'), 2)} × ${boss.name ? boss.name + '\'s' : 'the'} bite ${fmtN(bite, 0)} = <b>${fmtN(M.hitDamage(d, bite, 1), 1)}</b> before the stage, level and map factors; knockback ${fmtN(M.topVal(d, 'knockback'), 1)}${M.topVal(d, 'lift') > 0 ? ', lift ' + fmtN(M.topVal(d, 'lift'), 1) : ''}`);
    side.appendChild(facts);
    side.appendChild(el('p', { class: 'muted small', text: 'From above, to scale. The game turns and jitters a rain\'s layout at random every time it fires; this is one example with the same rules (the gap rule holds in every one).' }));
    wrap.appendChild(side);
    return wrap;
  }

  let _raf = 0;
  function tick(dur) {
    cancelAnimationFrame(_raf);
    let last = performance.now();
    const step = (now) => {
      if (!S.playing || App.S.tab !== 'bossattacks') { S.playing = false; return; }
      S.t = Math.min(dur, (S.t || 0) + (now - last) / 1000);
      last = now;
      if (S.t >= dur) S.playing = false;
      redraw();
      if (S.playing) _raf = requestAnimationFrame(step);
    };
    _raf = requestAnimationFrame(step);
  }

  // ------------------------------------------------------------------ keys (this tab's own Ctrl+S / Z / Y)

  if (typeof window !== 'undefined') {
    window.addEventListener('keydown', (e) => {
      if (typeof App === 'undefined' || App.S.tab !== 'bossattacks') return;
      const ctrl = e.ctrlKey || e.metaKey;
      if (!ctrl) return;
      const k = e.key.toLowerCase();
      const tgt = e.target;
      const typing = tgt && (tgt.tagName === 'INPUT' || tgt.tagName === 'TEXTAREA');
      if (k === 's') { e.preventDefault(); e.stopImmediatePropagation(); if (typing && tgt.blur) tgt.blur(); setTimeout(save, 0); return; }
      if (typing) return;
      if (k === 'z' && !e.shiftKey) { e.preventDefault(); e.stopImmediatePropagation(); undo(); return; }
      if (k === 'y' || (k === 'z' && e.shiftKey)) { e.preventDefault(); e.stopImmediatePropagation(); redo(); }
    }, true);
    window.addEventListener('beforeunload', (e) => { if (dirty()) { e.preventDefault(); e.returnValue = ''; } });
  }

  // ------------------------------------------------------------------ the Instructions tab's section

  function instructions(root) {
    const p = (h) => { const x = el('p'); x.innerHTML = h; return x; };
    const li = (h) => { const x = el('li'); x.innerHTML = h; return x; };
    const ol = (...steps) => el('ol', { class: 'howto' }, steps.map((s) => li(s)));
    const how = (title, steps) => { root.appendChild(el('h3', { text: title })); root.appendChild(steps); };
    root.appendChild(el('h2', { text: 'Pass 72: boss HP pegged to DPS, custom boss attacks' }));
    root.appendChild(el('h3', { text: 'Boss HP pegged to the hero\'s DPS (Settings → Boss HP)' }));
    const ul = el('ul', {});
    for (const w of (typeof BossScaling !== 'undefined' ? BossScaling.WORDS : [])) ul.appendChild(li(w));
    root.appendChild(ul);
    how('Tune it', ol(
      'Settings → <b>Boss HP</b>: <i>Peg boss HP to DPS</i> on; the <i>Exponent</i> (0.5), the <i>DPS window</i> (45 s), the <i>Floor</i> (0.75) and the <i>Ceiling</i> (3).',
      'Each boss\'s <b>reference DPS</b>: the DPS at which it keeps its data HP. A bigger reference = an easier boss for everyone below it. Pick a boss under the chart to see its curves; move the mouse over the chart to read any DPS.',
      'Measure a reference again after a balance change: <code>bash tools/godot.sh --headless --fixed-fps 60 --path game --script res://tools/difficulty_probe.gd -- t0=785 secs=75 stage=1 level=33 build=b2 mirror=1.5 hero=calavera seed=11</code> (the window ending at the boss\'s time) and read the <code>DPS45</code> line; <code>boss=1</code> plays on through the fight and prints its length, <code>scale=0</code> plays it at data HP.',
      'Save (the map\'s Save): the next run plays it.'));
    root.appendChild(el('h3', { text: 'Custom boss attacks (the Boss attacks tab)' }));
    root.appendChild(p('A custom attack is a content folder (<code>content/boss_attacks/&lt;id&gt;/&lt;id&gt;.json</code>) a boss\'s script names like a built-in: <code>{"name": "cactus_rain"}</code>. Its kind is one the game knows how to play; everything else is numbers. The Gila Grande\'s red cactus rain is the first one (it replaced its rumble).'));
    const kinds = el('ul', {});
    for (const k of KIND_OPTS) kinds.appendChild(li(`<b>${k.v}</b>: ${k.help}`));
    root.appendChild(kinds);
    how('Make one and give it to a boss', ol(
      'Boss attacks tab → <b>+ New attack</b>: a name (the id follows it), <i>Start from</i> a blank kind or a copy of an attack → <b>Make it</b>. It is written and imported at once.',
      'Tune it with the preview: the boss, the hero to scale 8 m off, the landing spots and the narrowest gap (the yellow line), the time slider and <b>▶ Play</b> (circles show red before their shot lands, landed spots fill in its colour). <b>New layout</b> throws another random turn and jitter (the game throws one every time).',
      'Every box shows the game\'s default in grey; <b>?</b> says what it does. Save attack (Ctrl+S). Ctrl+Z / Ctrl+Y step back and forth.',
      'Tick the bosses under <i>In the script of</i>: it goes to the end of their attack cycle (Enemies tab → the boss → <i>Attack script</i> to reorder it, give it a <i>Skip inside / beyond</i> range or its own wind-up for that boss).',
      '<b>Delete…</b> takes it out of every script first and moves the folder to the editor\'s backups.'));
    const keys = el('ul', {});
    for (const [g, title] of SECTIONS) {
      const rows = FIELDS.filter((f) => f.g === g);
      keys.appendChild(li(`<b>${title}</b> (<code>${g === '_top' ? 'damage, knockback, lift' : g}</code>): ` + rows.map((f) => `<i>${f.label}</i> (<code>${f.k}</code>, ${f.kinds.join('/')}): ${f.help}`).join('; ')));
    }
    root.appendChild(el('h3', { text: 'Every key' }));
    root.appendChild(keys);
  }

  return { render, options, get, open, ids: () => attacks().map((a) => a.id), save, undo, redo, instructions, FIELDS, SECTIONS, S };
})();
if (typeof module !== 'undefined') module.exports = BossAttacks;
