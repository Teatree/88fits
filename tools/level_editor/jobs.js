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
//
// Pass 68 (lane W): the tab draws UP NEXT first (the queued jobs in the order the workers take them: by lane, the
// server's list order with a resuming pick first, numbered per lane), then waiting, running, finished. In the form a NEW
// look (a new code, or a draft's Generate…) comes with at least 3 icon candidates (a creature) or 3 badge and 3 title
// cut-out candidates (a hero): jobs of their own, queued after the look with its Model settings and empty words that
// the server fills. The re-roll radios send spec.reroll {mode, view}. Badge, title and icon jobs show their words and
// their reference picture filled from GET /api/jobs/defaults, editable, each tagged with where it came from. The 2D / 3D
// reference rows (no tool read them) are gone: each method says where its picture goes instead. The review fixes: a job
// the server holds (`held`: a look's candidates waiting for its front still) shows after the runnable ones of its lane,
// unnumbered and unmovable, and ▲ / ▼ swap a card with its neighbour on screen (resuming picks among themselves, as the
// server's jobs.move does); an edit
// that clears a candidate field sends '' so the server fills it again; the badge and cut-out texts say where the game
// shows the pick (the cut-out only on the Painted title).
'use strict';

const Jobs = (() => {
  const { el, clear, fmtT } = U;
  const FAST = 2000, SLOW = 6000, MISSING = 15000;
  const LOG_LINES = 12;
  const COMFY_URL = 'http://192.168.137.54:8188/';   // the AI server's ComfyUI page (the workflow files are dragged into it)
  const STATES = ['running', 'waiting', 'queued', 'done', 'failed', 'interrupted', 'cancelled'];
  const FINISHED = ['done', 'failed', 'interrupted', 'cancelled'];
  const STATE_LABEL = { queued: 'QUEUED', running: 'RUNNING', waiting: 'WAITING FOR PICK', done: 'DONE', failed: 'FAILED', interrupted: 'INTERRUPTED', cancelled: 'CANCELLED' };
  // pass 68 (D12): the upcoming jobs at the top, in the order the workers take them (Garry: "the upcoming jobs show under
  // the running job"); one worker per lane, so the numbering is per lane
  const GROUPS = [['queued', 'Up next'], ['waiting', 'Waiting for a pick'], ['running', 'Running'], ['finished', 'Finished']];
  const LANE_ORDER = ['comfy', 'godot', 'local'];
  const TAB_OF_KIND = { enemy: 'creatures', boss: 'creatures', hero: 'heroes', weapon: 'items', evolution: 'items', passive: 'items', mutation: 'items', perk: 'heroes' };   // pass 69: perks
  const ROLES = [{ v: 'identity', label: 'identity (what it looks like)' }, { v: 'style', label: 'style (how it is drawn)' }, { v: 'pose', label: 'pose and anatomy' }];
  const FOLLOW = [{ v: 'loosely', label: 'follow loosely' }, { v: 'closely', label: 'follow closely' }, { v: 'copy', label: 'copy exactly' }];
  const USES = [{ v: 'animation', label: 'animation (how it moves)' }, { v: 'look', label: 'look (the painting reference)' }, { v: 'icon', label: 'icon (the icon render)' }];
  // the re-roll modes a look job carries as spec.reroll {mode, view} (pass 68, D3: the server applies them when it queues
  // the job); `only` = the methods a mode exists for
  const REROLL = [
    { v: 'seeds', label: 'new seeds', help: 'the stills painted again under new seeds and the clips made again from them (their folders move to <key>_old<stamp>, anim_seed + 1); a look that shares the creature\'s or the hero\'s paintings gets its own first, so those are never touched' },
    { v: 'clips', label: 'keep the stills, redo the clips', help: 'the stills stay; the clip folders move to <key>_old<stamp> and the walks are made again (anim_seed + 1)' },
    { v: 'view', label: 'redo one view', help: 'one view painted again as candidates to pick from (gen_ctl --view-cands)', only: ['creature_ctl'] },
    // pass 70 (lane LE): one view's walk again, on the driver the recipe names for that view now (May's side, Jezyk's back)
    { v: 'clip', label: 'redo one view\u2019s walk', help: 'only that view\u2019s clip moves to <key>_old<stamp> and is walked again, on the driver the recipe names for that view now (anim_seed + 1); the stills and the other views stay' },
    { v: 'stills', label: 'repaint the stills', help: 'the stills painted again under new seeds (a look sharing the paintings gets its own first); the clips are walked again from the new stills (same clip seeds); "new seeds" also rolls new clip seeds' },
    // pass 71 (lane PLE): a puppet look made again from one puppet stage (puppet.py --reset-from: that stage's outputs and
    // the later ones move to tools/dl/puppet/<hero>/old/<stamp>/)
    { v: 'stage', label: 'run the puppet again from a stage', help: 'the puppet is made again from the stage chosen (the arms-out paintings, the shape, the rig, the clips, the guides): its outputs and the later ones move to old/<stamp>/; then the walks', only: ['hero_puppet'] },
  ];
  // the modes jobs.py's _apply_reroll accepts per method (it refuses the others with a reason): hero_fit paints no stills
  // of its own, gen_ctl paints its stills from the picked side, creature_proc has no clips; a recolour and a front from a
  // picture have nothing to re-roll
  const REROLL_FOR = { hero_fit: ['clips', 'clip'], creature_ctl: ['clips', 'clip', 'view'], creature_proc: ['seeds', 'stills'], creature_pictures: ['seeds', 'stills'], recolour: [], front_from_picture: [], hero_puppet: ['seeds', 'clips', 'clip', 'stills', 'stage'] };
  function rerollModes(method) { return REROLL.map((r) => r.v).filter((v) => (REROLL_FOR[method] || ['seeds', 'clips', 'clip', 'stills']).includes(v)); }
  // the look methods whose stills are cached under a slug of the look's own (jobs.py STILL_METHODS, pass 68 D1: hero_pose5
  // joined); a Duplicate… draft of one of them can reuse its source's paintings
  const STILL_METHODS = ['creature_free2', 'creature_pose2', 'creature_free8', 'creature_proc', 'creature_pictures', 'hero_pose5', 'hero_puppet'];
  // pass 68 (D10): a new look comes with at least this many candidates of each kind it has
  const MIN_CANDIDATES = 3;
  // the candidate jobs and the fields their tools read (D6/D7); "What to paint" shows them filled from the server's
  // defaults (GET /api/jobs/defaults), editable; they are job fields (SPECS), so flatten keeps them
  const CAND_KINDS = ['icon_cands', 'hero_badge', 'hero_title'];
  // pass 72 (Garry: "first seed" on every asset that has candidates): the two fields every candidate form shows, with
  // the same words (jobs.py CANDIDATES_HELP / FIRST_SEED_HELP; the served SPECS' help wins when it is there); the look
  // methods that stop for a pick of candidates; the puppet's arms-out fronts show them too (puppet.js)
  const CANDIDATES_HELP = 'how many candidates to paint and pick from, each on a seed of its own';
  const FIRST_SEED_HELP = 'where this job\'s seeds start: candidate k paints on the first seed + k × 1,000,003, the whole set moved by this job\'s id and by every re-run, so no two jobs paint the same pictures (tools/cand_seeds.py); 0 = the tool\'s own start, from the asset\'s id; another number = a fresh set from the same words';
  const SEEDED_LOOKS = ['creature_ctl', 'front_from_picture'];
  const CHARACTER_HELP = 'who is painted, in words: the look\'s `appearance` when it has one, else its art_prompt with the pose clause cut (a portrait must not inherit "standing straight, arms at her sides"); the words go right after "this exact character"';
  const CAND_FIELDS = {
    hero_badge: [
      { key: 'character', label: 'Character', type: 'textarea', help: CHARACTER_HELP },
      { key: 'prompt', label: 'Action', type: 'textarea', help: 'what the portrait does: the expression and the gesture (the hero\'s portrait_prompt by default)' },
      { key: 'ref', label: 'Reference picture', type: 'picture', help: 'the picture the portraits are edited from (the identity): the look\'s own front still by default; any picture can take its place (an upload, a turnaround)' },
    ],
    hero_title: [
      { key: 'character', label: 'Character', type: 'textarea', help: CHARACTER_HELP },
      { key: 'pose', label: 'Pose', type: 'textarea', help: 'the pose of the full-body splash: the hero\'s title_pose, else the tool\'s own table, else "standing confidently in a heroic pose, full body"' },
      { key: 'holds', label: 'Holds', type: 'text', help: 'the one thing held (title_holds): "the guitar is the only thing he holds"' },
      { key: 'camera', label: 'Camera', type: 'text', help: 'the shot (title_camera): "facing the viewer, seen from the front at eye level"' },
      { key: 'ref', label: 'Reference picture', type: 'picture', help: 'the identity picture: the look\'s own front still by default' },
      { key: 'extra_ref', label: 'Extra reference', type: 'picture', help: 'optional: a picture of the held object, copied exactly (title_extra_ref.file)' },
      { key: 'extra_words', label: 'Extra reference words', type: 'text', help: 'what the extra picture is (title_extra_ref.words): "copy its shape and colours exactly: <words>"' },
    ],
    icon_cands: [
      { key: 'subject', label: 'Subject', type: 'textarea', help: 'what to paint: a creature\'s character words, an item\'s art_prompt' },
      { key: 'ref', label: 'Reference picture', type: 'picture', help: 'a creature look\'s front still by default (an item: none unless it has a 3D render); with a picture the words begin "The reference image shows this exact creature: keep its shape, colors and proportions."' },
      { key: 'screen', label: 'Screen', type: 'select', options: ['green', 'blue'], help: 'the screen colour the icon is painted on (blue for anything with green in it)' },
      { key: 'file', label: 'Icon file', type: 'text', help: 'the file the pick installs: <id>_icon_<letter>.png for a look (its own icon, variants[CODE].icon), <id>_icon.png for the base' },
    ],
  };
  // the look job's fields only one method's tool reads (D11): hidden from the others' form
  const METHOD_ONLY = {
    ref: ['front_from_picture'], prompt: ['front_from_picture'], keep: ['front_from_picture'], stills: ['front_from_picture'], picture: ['front_from_picture'], pick: ['front_from_picture'],
    no_style_ref: ['front_from_picture'], stage: ['creature_ctl'], use_side: ['creature_ctl'], view_cands: ['creature_ctl'], use_view: ['creature_ctl'], recolour: ['recolour'],
  };
  // the words the tools put round the fields (gen_art.STYLE, BG_GREEN / BG_BLUE, ICON_STYLE), for "Show the words"
  const STYLE_WORDS = 'in a clean modern anime art style: crisp confident line art, cel shading with two-tone shadows and sharp highlights, flat saturated colors, appealing stylized proportions, simple readable shapes with no texture noise, like character art from a Japanese action RPG mobile game. Game asset';
  const BG_WORDS = {
    green: 'isolated on a flat solid bright green (#00FF00) background that fills the entire frame, floating in empty space with no ground plane, no cast shadow, no grass, no text, no watermark',
    blue: 'isolated on a flat solid bright blue (#0000FF) background that fills the entire frame, floating in empty space with no ground plane, no cast shadow, no grass, no text, no watermark',
  };
  const ICON_STYLE_WORDS = 'Mobile game item icon in the style of Shop Titans: one single bold object, thick clean black outline, simple chunky shapes, flat cel shading with one soft highlight, saturated high-contrast colors, centered and filling the frame with a small margin, readable at thumbnail size, no text, no background, no scene';
  const S = {
    rev: 0, jobs: [], status: null, statusAt: 0, timer: 0, last: null, hidden: new Set(), apiMissing: false, panel: null,
    groups: null, cards: new Map(), sigs: new Map(), methods: null, methodsP: null, drivers: null, refs: null, lists: {}, confirm: null, started: false,
    specs: undefined,   // GET /api/jobs/specs: jobs.py's SPECS {kind: {lane, fields: {name: {type, default, required, help, options}}}}; null = not served
  };
  // a job's spec as jobs.py validates it is FLAT (method, recipe, refs, drivers, skip_qa, dev, seed, seeds, keys, ...);
  // the form edits a nested state (flags, counts, job) and flattens it on Queue / Save (flatten), unflattens on Edit
  const FLAG_KEYS = ['skip_qa', 'dev', 'no_video', 'no_style_ref'];
  const OWN_KEYS = ['method', 'recipe', 'refs', 'drivers', 'note', 'seed', 'seeds', 'reroll'].concat(FLAG_KEYS);

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
    if (spec.reroll && spec.reroll.mode) out.reroll = spec.reroll.mode === 'view' ? { mode: 'view', view: spec.reroll.view || 'front' } : spec.reroll.mode === 'stage' ? { mode: 'stage', stage: spec.reroll.stage || 'guides' } : { mode: spec.reroll.mode };
    // front_from_picture's slug is a recipe field in the form and a job field in jobs.py (its argv reads spec.stills)
    if (spec.method === 'front_from_picture' && (out.stills == null || out.stills === '') && spec.recipe && spec.recipe.stills) out.stills = spec.recipe.stills;
    const fields = specs && specs[jk] && specs[jk].fields && typeof specs[jk].fields === 'object' ? specs[jk].fields : null;
    if (fields) {
      for (const k of Object.keys(out)) if (!(k in fields)) delete out[k];
      for (const [k, f] of Object.entries(fields)) if (out[k] === undefined && f && f.required && f.default !== undefined && f.default !== null && f.default !== '') out[k] = f.default;
    }
    return out;
  }
  /** An edited candidate job's flat spec: every candidate field missing or empty goes out as ''. flatten leaves empty
   *  values out and the server's edit merges the posted spec over the stored one, so a field cleared in the form would
   *  keep its old value; '' makes the server fill it again from the defaults (D6: also in edit), as the field's tag says,
   *  or leave it empty when there is no default. Other kinds as they are. */
  function withClearedFields(jk, flat) {
    if (CAND_KINDS.includes(jk)) for (const f of CAND_FIELDS[jk] || []) if (flat[f.key] == null || flat[f.key] === '') flat[f.key] = '';
    return flat;
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

  // ------------------------------------------------------------------ pass 68: pure helpers (selftest_V runs them under Node)

  /** The queued jobs in the order the workers take them (D12, jobs.py _take_next): by lane (comfy, godot, local, then any
   *  other); within a lane a `front` job (a picked job resuming) first, then the server's list order; a `held` job (the
   *  server's mark: a candidate job whose reference is its look's front still, not painted yet, while that look's job is
   *  live; _take_next skips it) after the runnable ones of its lane, unnumbered. Returns [{job, pos, n, held, up, down}]:
   *  pos = the place among the lane's runnable jobs (n of them; -1 for a held job); up / down = the `delta` a ▲ / ▼ move
   *  sends (0 = the button is off). jobs.move swaps a job with its neighbour in its own group (the same lane, front flag
   *  and hold, in list order: the order shown here), so ▲ / ▼ send -1 / +1 and are off at a group's ends: a resuming pick
   *  never trades places with the others (the worker takes it first whatever the list says), and a held job does not move. */
  function queueOrder(queued) {
    const li = (l) => { const i = LANE_ORDER.indexOf(l || ''); return i < 0 ? LANE_ORDER.length : i; };
    const lanes = new Map();
    for (const j of queued || []) { const l = j.lane || ''; if (!lanes.has(l)) lanes.set(l, []); lanes.get(l).push(j); }
    const out = [];
    for (const l of [...lanes.keys()].sort((a, b) => (li(a) - li(b)) || a.localeCompare(b))) {
      const peers = lanes.get(l);
      const groups = [peers.filter((j) => j.front && !j.held), peers.filter((j) => !j.front && !j.held)];
      const n = groups[0].length + groups[1].length;
      let pos = 0;
      for (const g of groups) g.forEach((j, k) => out.push({ job: j, pos: pos++, n, held: false, up: k > 0 ? -1 : 0, down: k < g.length - 1 ? 1 : 0 }));
      for (const j of peers.filter((x) => x.held)) out.push({ job: j, pos: -1, n, held: true, up: 0, down: 0 });
    }
    return out;
  }
  function queueLabel(pos, n, lane) { return `#${pos + 1} of ${n} in the ${lane || '?'} lane${pos === 0 ? ' · next' : ''}`; }
  /** A held job's place: it waits for its look's front still (the picture its candidates are painted from). */
  function heldLabel(j) { const t = (j && j.target) || {}; return `waiting for ${t.code || t.id || 'its look'}'s front`; }

  /** The painter the form's Model settings make, in jobs.py _painter_of's shape {model, steps[, guidance, turbo]}. */
  function painterOfSpec(spec) {
    const j = (spec && spec.job) || {};
    const dev = j.model === 'dev' || (j.model == null && !!(spec && spec.flags && spec.flags.dev));
    const out = { model: dev ? 'dev' : 'klein', steps: Number(j.steps) || 0 };
    if (dev) { out.guidance = Number(j.guidance) || 0; out.turbo = j.turbo !== false; }
    return out;
  }
  /** Whether two painters would paint a still differently: the model, the passes, and for dev the guidance and Turbo
   *  (recipe.painter's bookkeeping keys, stills and reused, do not count). */
  function painterDiffers(a, b) {
    const n = (p) => { const x = p && typeof p === 'object' ? p : {}; const dev = x.model === 'dev'; return [dev ? 'dev' : 'klein', Number(x.steps) || 0, dev ? Number(x.guidance) || 0 : 0, dev ? x.turbo !== false : true].join('|'); };
    return n(a) !== n(b);
  }

  /** The candidate jobs a NEW look comes with (D10): a creature's icon candidates; a hero's round badge and title
   *  cut-out candidates. None for a recolour (it recolours its source's icon) or a front from a picture (it paints no
   *  look: the candidates come with the look painted from it). */
  function candidatePlan(kind, method) {
    if (method === 'recolour' || method === 'front_from_picture') return [];
    if (kind === 'hero') return [{ jk: 'hero_badge', count: 'icon_candidates', label: 'badge candidates' }, { jk: 'hero_title', count: 'cutout_candidates', label: 'title cut-out candidates' }];
    if (kind === 'enemy' || kind === 'boss') return [{ jk: 'icon_cands', count: 'icon_candidates', label: 'icon candidates' }];
    return [];
  }
  /** Queue's refusal for a new look whose counts are under the minimum, or '' (Garry: "at least 3 each, required"). */
  function candidateRefusal(plan, counts) {
    const c = counts || {};
    const short = (plan || []).filter((p) => !(Number(c[p.count]) >= MIN_CANDIDATES));
    if (!short.length) return '';
    return `a new look comes with at least ${MIN_CANDIDATES} ${short.map((p) => p.label).join(' and ')}: raise ${short.length > 1 ? 'the counts' : 'the count'} under Looks`;
  }

  /** A picture path as the page can show it: tools/dl/<x>, a tools/dl-relative path or an absolute path inside tools/dl
   *  through /dl/ (where the server serves the uploads, the stills, the clips, the review sheets and the title
   *  candidates); a /dl/ or /art/ URL as it is; anything else has no preview here (''). */
  function refUrl(p) {
    let s = String(p || '').trim().replace(/\\/g, '/');
    if (!s) return '';
    if (/^\/(dl|art|icon|sprite)\//.test(s)) return s;
    const i = s.toLowerCase().lastIndexOf('/tools/dl/');
    if (i >= 0) s = s.slice(i + '/tools/dl/'.length);
    else if (s.startsWith('tools/dl/')) s = s.slice('tools/dl/'.length);
    else if (/^[a-zA-Z]:\//.test(s) || s.startsWith('/') || /^(_REFERENCES|game|tools|docs)\//.test(s)) return '';
    return '/dl/' + s.split('/').filter(Boolean).map(encodeURIComponent).join('/');
  }

  /** The prompt a candidate tool builds from its fields (D7: gen_badge_cands, gen_title_heroes, gen_icon_cands), for
   *  "Show the words"; o = {screen: green | blue, creature: bool}. The authoritative text is asset_job.py --dry-run's. */
  function candidateWords(jk, f, o) {
    const x = f || {}, opt = o || {};
    const bg = BG_WORDS[opt.screen === 'green' ? 'green' : 'blue'];
    // the tools' clean_words: the words as typed, without a trailing comma, semicolon or full stop
    const who = String(x.character || '').trim().replace(/[\s,;.]+$/, '');
    if (jk === 'hero_badge') {
      return 'A close-up portrait of this exact character for a mobile game avatar icon: ' + (who ? who + ', ' : '') +
        'only the head and shoulders, the head filling half of the frame, ' + (x.prompt || 'smiling at the viewer') + ', facing the viewer, the shoulders and chest running off the bottom edge of the frame, expressive and lively, no legs, no full body. Keep the same face, outfit, colors and art style as the reference. ' + bg + '.';
    }
    if (jk === 'hero_title') {
      const extra = String(x.extra_words || '');
      return 'A full-body character illustration of this exact character' + (who ? ', ' + who + ',' : '') + ' for a mobile game\'s hero select screen: ' +
        (x.pose || 'standing confidently in a heroic pose, full body') + ', ' + (x.camera || 'facing the viewer, seen from the front at eye level') +
        ', the whole figure visible from the top of the head down to the feet with empty space around it, ' + (x.holds || 'no weapon') + '. ' +
        (extra ? extra + (extra.endsWith(' ') ? '' : ' ') : '') + 'Keep the same face, outfit, colors and proportions as the reference. ' + STYLE_WORDS + '. ' + bg + '.';
    }
    if (jk === 'icon_cands') {
      // gen_icon_cands.icon_words: with a picture the words lead with what it shows (a creature, a character, else an
      // object to copy) unless the subject already speaks of "the reference image"
      const ibg = BG_WORDS[x.screen === 'blue' ? 'blue' : 'green'];
      let subj = String(x.subject || '').trim();
      if (subj.endsWith('.')) subj = subj.slice(0, -1).trimEnd();
      const lead = !x.ref || /reference image/i.test(subj) ? '' : opt.creature ? 'The reference image shows this exact creature: keep its shape, colors and proportions. '
        : opt.character ? 'The reference image shows this exact character: keep the same face, outfit, colors and proportions. '
          : 'Copy this exact object from the reference image: its silhouette, proportions, parts and colours, seen from the same angle. ';
      return lead + (subj ? subj + '. ' : '') + (x.style || ICON_STYLE_WORDS) + '. ' + ibg + '.';
    }
    return '';
  }

  /** Where a candidate field's value came from: the server's source while it equals the default, else the editor's. */
  function sourceTag(key, value, d) {
    const dv = d && d.fields ? d.fields[key] : undefined;
    const src = d && d.sources ? d.sources[key] : '';
    const has = (v) => v != null && v !== '';
    if (!has(value)) return has(dv) ? `empty: the server fills it from ${src || 'its default'} when the job is queued` : 'empty: the tool\'s own fallback';
    if (has(dv) && String(value) === String(dv)) return src ? `from ${src}` : 'the default';
    return 'yours: typed or picked here';
  }

  /** GET /api/jobs/defaults (D6): {fields, sources, ref_url, ref_exists} for a candidate job's target; {error} when the
   *  server has none yet (the fields then stay empty and the tools fall back to the hero's own words). */
  async function fetchDefaults(jk, kind, id, code) {
    const target = `${kind}/${id}${code ? '/' + code : ''}`;
    try {
      const r = await fetch(`/api/jobs/defaults?kind=${encodeURIComponent(jk)}&target=${encodeURIComponent(target)}`, { cache: 'no-store' });
      if (r.status === 404) return { jk, target, fields: {}, sources: {}, error: 'the server has no /api/jobs/defaults route yet' };
      let d = null;
      try { d = await r.json(); } catch (_) { d = null; }
      if (!r.ok || !d || d.ok === false) return { jk, target, fields: {}, sources: {}, error: (d && d.error) || `HTTP ${r.status}` };
      const x = d.defaults && typeof d.defaults === 'object' ? d.defaults : d;
      return { jk, target, fields: x.fields && typeof x.fields === 'object' ? x.fields : {}, sources: x.sources && typeof x.sources === 'object' ? x.sources : {},
        ref_url: x.ref_url || null, ref_exists: typeof x.ref_exists === 'boolean' ? x.ref_exists : null };
    } catch (e) { return { jk, target, fields: {}, sources: {}, error: e.message }; }
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
    // a look card shows its jobs' states, and a stub without a live look job is a draft with Generate… (pass 68): the open
    // grid is told when the set of live jobs per look changes; it draws itself again only when its own asset's changed and
    // no edit or confirm box is open on it (LookGrid.jobsChanged)
    const live = JSON.stringify(jobs.filter((j) => ['queued', 'running', 'waiting'].includes(j.state) && j.target && j.target.code).map((j) => [j.target.kind, j.target.id, j.target.code, j.kind, j.state]));
    if (live !== S.liveSig) {
      S.liveSig = live;
      if (typeof LookGrid !== 'undefined' && typeof LookGrid.jobsChanged === 'function') { try { LookGrid.jobsChanged(); } catch (_) { /* drawn on the next render */ } }
    }
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
    let res = await post(`/api/jobs/${encodeURIComponent(j.id)}/${path}`, body);
    // pass 76 (lane ICON): an icon for the look in play or the base asks first (now -> new), then goes with confirm: true
    if (res && res.confirm_needed && path === 'install' && typeof LookGrid !== 'undefined' && LookGrid.confirmIconChange) {
      if (!(await LookGrid.confirmIconChange(res))) { App.status(`${title(j)}: not installed, nothing changed`); return res; }
      res = await post(`/api/jobs/${encodeURIComponent(j.id)}/${path}`, Object.assign({}, body, { confirm: true }));
    }
    if (!res.ok) { App.status(`${title(j)}: ${path} refused: ${res.error}`, 'bad', res.output || ''); return res; }
    App.status(`${title(j)}: ${path} done`, 'good');
    await poll();
    return res;
  }

  function openAsset(t) {
    if (!t || !t.kind || !t.id) return;
    if (t.kind === 'sim') { App.switchTab('sim'); return; }   // pass 77 (lane SIMUI): a sim's charts are in the Sim tab
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
    const ro = st.jobs && st.jobs.readonly;
    if (ro) {
      // a second Level Editor: the first one holds the queue (jobs.claim_queue); this page shows it and refuses changes
      const since = ro.since && isFinite(Number(ro.since)) ? new Date(Number(ro.since) * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : (ro.since || '?');
      box.appendChild(el('div', { class: 'jwarn', text: ro.view_only ? 'This editor was started with --no-jobs: it shows the queue and changes nothing. Queue from the editor that runs it.'
        : `Another Level Editor runs the job queue (${ro.who || 'level_editor'}, pid ${ro.pid || '?'}, since ${since}; the other editor window, on another port). This page shows the queue read-only and refuses changes: queue from that page, or close it and restart this one. A lock left by an editor that is gone: Force release on "Job queue" below, then restart this one.` }));
    }
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
    box.appendChild(lock('jobs', 'Job queue'));
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
    return JSON.stringify([j.state, j.waiting_for, p.stage, p.done, p.total, p.stalled, (j.log_tail || []).slice(-1)[0], (j.outputs || []).length, (j.outputs || []).filter((o) => o.open_url).length, S.status && S.status.comfy_open_ext ? S.status.comfy_open_ext.installed : null, (j.choices || []).length, j.ended, j.error, j.written && j.written.layout, j.merged_into, j.eta_s, j.state === 'running' ? Math.floor(Date.now() / 2000) : 0, S.hidden.has(j.id), !!j.front, !!j.held, j.lane]);
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
    by.finished.sort((a, b) => String(b.ended || b.created || '').localeCompare(String(a.ended || a.created || '')));
    // Up next in the order the workers take the jobs, numbered per lane, held jobs after (D12); the other groups as the
    // server lists them
    const ordered = { queued: queueOrder(by.queued) };
    for (const key of ['running', 'waiting', 'finished']) ordered[key] = by[key].map((j, i) => ({ job: j, pos: i, n: by[key].length }));
    for (const [key, label] of GROUPS) {
      const list = ordered[key];
      if (!list.length) continue;
      let head = `${label} · ${list.length}`;
      if (key === 'queued') {
        const per = {}, held = {};
        for (const x of list) { const l = x.job.lane || '?'; per[l] = (per[l] || 0) + 1; if (x.held) held[l] = (held[l] || 0) + 1; }
        if (Object.keys(per).length > 1 || Object.keys(held).length) head += ` (${Object.entries(per).map(([l, n]) => `${l} ${n}${held[l] ? `, ${held[l]} waiting for a front` : ''}`).join(' · ')})`;
      }
      const g = el('div', { class: 'jobs-group' + (key === 'queued' ? ' upnext' : '') }, el('h2', { text: head, title: key === 'queued' ? 'in the order they will run: one job at a time per lane (comfy: the art; godot: imports and launches; local: Blender, pose tools, recolours, installs), the lanes side by side; a job waiting for a look\'s front still runs once that picture is painted' : '' }));
      list.forEach((x) => {
        const j = x.job;
        const s = sig(j);
        const where = [x.pos, x.n, x.held ? 1 : 0, x.up || 0, x.down || 0].join('/');
        let c = S.cards.get(j.id);
        if (!c || S.sigs.get(j.id) !== s || c.dataset.pos !== where) {
          if (c) disposeCard(c);        // the old card's clip players go with it (a running card is rebuilt every poll)
          c = card(j, x); c.dataset.pos = where; S.cards.set(j.id, c); S.sigs.set(j.id, s);
        }
        g.appendChild(c);
      });
      S.groups.appendChild(g);
    }
    for (const id of [...S.cards.keys()]) if (!jobs.some((j) => j.id === id)) { disposeCard(S.cards.get(id)); S.cards.delete(id); S.sigs.delete(id); }
  }

  function disposeCard(c) { for (const p of (c && c.__players) || []) p.destroy(); if (c) c.__players = []; }

  // ------------------------------------------------------------------ the cards

  /** A job's card; x = its place ({pos, n} in its group; queued jobs: queueOrder's entry with held, up, down). */
  function card(j, x) {
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
    // pass 68 (D6): the fields the server filled from the defaults when the job was queued, and where each came from
    const df = j.spec && j.spec.defaults_from && typeof j.spec.defaults_from === 'object' ? Object.entries(j.spec.defaults_from) : [];
    if (df.length) sub.appendChild(el('span', { class: 'muted', text: 'filled in: ' + df.map(([k, v]) => `${k} from ${v || 'the defaults'}`).join(' · '), title: df.map(([k]) => `${k}: ${String(j.spec[k] == null ? '' : j.spec[k]).slice(0, 200)}`).join('\n') }));
    if (j.spec && j.spec.reroll && j.spec.reroll.mode) sub.appendChild(el('span', { class: 'muted', text: `re-roll: ${j.spec.reroll.mode}${j.spec.reroll.view ? ' (' + j.spec.reroll.view + ')' : ''}` }));
    if (j.qa_online === false) sub.appendChild(el('span', { class: 'warn-text', text: 'QA offline: every first roll kept', title: 'the vision check did not answer; the tools keep what the model painted first' }));
    c.appendChild(sub);
    if (j.state === 'running') runningBody(c, j);
    else if (j.state === 'waiting') waitingBody(c, j);
    else if (j.state === 'queued') queuedBody(c, j, x || { pos: 0, n: 1 });
    else if (j.state === 'done') doneBody(c, j);
    else failedBody(c, j);
    if (j.equiv) c.appendChild(el('details', { class: 'jfold' }, el('summary', { text: 'the command Claude would type' }), el('div', { class: 'jequiv', text: j.equiv })));
    if (j.spec) c.appendChild(el('details', { class: 'jfold' }, el('summary', { text: 'the spec' }), el('pre', { class: 'jlog', text: JSON.stringify(j.spec, null, 1) })));
    return c;
  }

  function stagesRow(j) {
    const p = j.progress || {};
    const row = el('div', { class: 'jstages' });
    // a stage's note says when it was not made by this job ("cached": the still or clip was on disk already)
    for (const s of p.stages || []) row.appendChild(el('span', { class: 'jstage ' + (s.state || '') + (s.note === 'cached' ? ' cached' : ''), text: s.name + (s.secs ? ` ${Math.round(s.secs)}s` : '') + (s.note ? ` · ${s.note}` : ''), title: `${s.name}: ${s.state || 'pending'}${s.note === 'cached' ? ' (reused from disk: this job did not paint it)' : s.note ? ' · ' + s.note : ''}` }));
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
      j.target && j.target.id ? el('button', { type: 'button', class: 'btn small', text: j.kind === 'sim' ? 'Open in Sim' : 'Open asset', onclick: () => openAsset(j.target) }) : null,
      el('button', { type: 'button', class: 'btn small ghost', text: 'Log', title: 'the last 80 lines', onclick: () => showLog(j) })));
  }

  function waitingBody(c, j) {
    const choices = j.choices || [];
    let picked = c.__picked || null;
    const what = { side: 'the side painting the other views follow', view: 'one view\'s candidates', pick: 'a candidate', puppet_front: 'the arms-out front the 3D shape is made from', puppet_views: 'one arms-out side and one back', puppet_shape: 'the 3D shape (each try in clay from six sides)' }[j.waiting_for] || 'a candidate';
    // pass 71: choices with a `group` (a puppet's side and back) take one pick per group, sent together ("side=1,back=0")
    const groups = [...new Set(choices.filter((ch) => ch.group).map((ch) => ch.group))];
    const gpicked = c.__gpicked || (c.__gpicked = {});
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
      if (ch.group && groups.length) {
        box.classList.toggle('picked', gpicked[ch.group] === key);
        box.addEventListener('click', () => {
          gpicked[ch.group] = key;
          for (const x of grid.children) if (x.dataset.group === ch.group) x.classList.toggle('picked', x === box);
          picked = groups.every((g) => gpicked[g]) ? (typeof Puppet !== 'undefined' ? Puppet.groupPick(gpicked) : Object.values(gpicked).join(',')) : null;
          c.__picked = picked;
          pickBtn.disabled = !picked;
          pickBtn.textContent = picked ? `Pick ${picked}` : `Pick (one per ${groups.join(' and ')})`;
        });
        box.dataset.group = ch.group;
      } else if (ch.sheet && !ch.key) {
        img.title = 'the review sheet';
      } else {
        box.addEventListener('click', () => { picked = key; c.__picked = key; for (const x of grid.children) x.classList.toggle('picked', x === box); pickBtn.disabled = false; pickBtn.textContent = `Pick ${ch.label || key}`; });
      }
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
    // pass 71: what the job made so far, its ComfyUI workflows above all (a puppet job stops for three picks)
    if (j.progress && (j.progress.stages || []).length) c.appendChild(stagesRow(j));
    if ((j.outputs || []).length) c.appendChild(outputs(j, c.__players));
  }

  /** A queued card: its place in its lane (x = queueOrder's entry: one worker per lane takes them in this order), or, for
   *  a held job, what it waits for; ▲ / ▼ swap it with the card above or below in its group (off where none is). */
  function queuedBody(c, j, x) {
    const { pos, n, held } = x;
    const up = held ? 0 : (x.up != null ? x.up : (pos > 0 ? -1 : 0)), down = held ? 0 : (x.down != null ? x.down : (pos < n - 1 ? 1 : 0));
    const t = j.target || {};
    c.appendChild(el('div', { class: 'jcard-sub' },
      held ? el('span', { class: 'warn-text', text: heldLabel(j), title: `held: its reference picture (${(j.spec && j.spec.ref) || 'the look\'s front still'}) is not on disk yet, and ${t.code || 'its look'}'s look job (queued, running or waiting for a pick) paints it first; the ${j.lane || '?'} lane runs the jobs above, and this one once that picture is there` })
        : el('span', { class: pos === 0 ? 'jnext' : 'muted', text: queueLabel(pos, n, j.lane), title: `the ${j.lane || '?'} lane runs one job at a time, in this order; the other lanes run beside it` }),
      j.front && !held ? el('span', { class: 'muted', text: 'a picked job resuming: it goes first in its lane' }) : null,
      j.eta_s != null ? el('span', { class: 'muted', text: `~${fmtT(j.eta_s)} once it runs`, title: 'the method\'s measured median × its stages' }) : null));
    // pass 71: a resuming job (a pick made, a puppet phase on the other lane next) shows what it made so far
    if ((j.phase || 1) > 1 && j.progress && (j.progress.stages || []).length) c.appendChild(stagesRow(j));
    if ((j.phase || 1) > 1 && (j.outputs || []).length) c.appendChild(outputs(j, c.__players));
    const why = held ? 'a held job waits for its look\'s front: it does not move' : j.front ? 'a picked job resuming goes first in its lane: it moves only among the other resuming ones' : 'a resuming pick stays first in the lane';
    c.appendChild(el('div', { class: 'jcard-actions' },
      el('button', { type: 'button', class: 'btn small', text: 'Edit', title: 'change the spec in the form', onclick: () => openForm(j.target.kind, j.target.id, { job: j }) }),
      el('button', { type: 'button', class: 'btn small', text: '▲', title: up ? 'earlier in its lane' : `earlier in its lane (${held ? why : pos === 0 ? 'it is first' : why})`, disabled: !up, onclick: () => act(j, 'move', { delta: up }, 'moving') }),
      el('button', { type: 'button', class: 'btn small', text: '▼', title: down ? 'later in its lane' : `later in its lane (${held ? why : pos >= n - 1 ? 'it is last' : why})`, disabled: !down, onclick: () => act(j, 'move', { delta: down }, 'moving') }),
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
      j.target && j.target.id ? el('button', { type: 'button', class: 'btn small primary', text: j.kind === 'sim' ? 'Open in Sim' : j.target.code ? 'Open look' : 'Open asset', onclick: () => openAsset(j.target) }) : null,
      el('button', { type: 'button', class: 'btn small', text: 'Re-queue', title: 'the same spec again (attempt + 1); the tools reuse what is cached unless you re-roll', onclick: () => act(j, 'requeue', {}, 're-queueing') }),
      j.kind === 'sim' ? null : el('button', { type: 'button', class: 'btn small', text: 'Re-roll…', title: 'choose which cached stills and clips to throw away, then re-queue', onclick: () => rerollPanel(c, j) }),
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
    if (j.outputs && j.outputs.length) c.appendChild(outputs(j, c.__players));   // what it made before it stopped: its workflows above all
    const t = j.target || {};
    c.appendChild(el('div', { class: 'jcard-actions' },
      el('button', { type: 'button', class: 'btn small primary', text: 'Re-queue', onclick: () => act(j, 'requeue', {}, 're-queueing') }),
      j.kind === 'sim' ? null : el('button', { type: 'button', class: 'btn small', text: 'Re-roll…', title: 'choose which cached stills and clips to throw away, then re-queue', onclick: () => rerollPanel(c, j) }),
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
    if (j.method === 'hero_puppet' && typeof Puppet !== 'undefined') Puppet.rerollStage(box, picks);   // pass 71
    const seedCb = el('input', { type: 'checkbox' }); seedCb.checked = true;
    box.appendChild(el('label', { class: 'cb' }, seedCb, el('span', { text: `the next seed (${seedOf(j)} → ${seedOf(j) + 1})` })));
    box.appendChild(el('div', { class: 'row' },
      el('button', { type: 'button', class: 'btn small primary', text: 'Re-queue', onclick: () => { const reroll = { stills: [...picks.stills], clips: [...picks.clips] }; if (seedCb.checked) reroll.seed = seedOf(j) + 1; if (picks.stage) reroll.stage = picks.stage; box.remove(); act(j, 'requeue', { reroll }, 're-rolling'); } }),
      el('button', { type: 'button', class: 'btn small ghost', text: 'Cancel', onclick: () => box.remove() })));
    c.appendChild(box);
  }

  /** The job's outputs: stills with their QA verdict, clips played from their out_NN frames, sheets, icons, the strip. */
  function outputs(j, holder) {
    const box = el('div', { class: 'joutputs' });
    const flows = (j.outputs || []).filter((o) => o.type === 'workflow');
    if (flows.length) {
      // the ComfyUI workflows this job ran, one per render. Each run also saves its graph into the ComfyUI page's own
      // Workflows sidebar (workflows/88fits/<job folder>/); "↗" opens the page on that copy through the 88fits_open
      // extension (Garry: "click a link and open the ComfyUI page with the workflow and everything"); "file" is the JSON.
      const ext = S.status && S.status.comfy_open_ext ? S.status.comfy_open_ext.installed : null;
      const unsent = flows.filter((o) => !o.open_url).length;
      const row = el('div', { class: 'jflows' }, el('b', { text: 'ComfyUI workflows' }),
        el('span', { class: 'muted small', text: unsent ? ' (one per render)' : ' (one per render; each sits in the ComfyUI page\'s Workflows sidebar under 88fits)' }));
      for (const o of flows) {
        const set = el('span', { class: 'jflow-set' });
        if (o.open_url) set.appendChild(el('a', { class: 'jflow open', href: o.open_url, target: '_blank', rel: 'noopener', text: o.label + ' ↗', title: ext === false ? `opens the ComfyUI page; its 88fits_open extension is not installed yet, so pick the workflow in the Workflows sidebar: ${o.userdata}` : `open the ComfyUI page on this workflow (${o.userdata})` }));
        else set.appendChild(el('span', { class: 'jflow pending', text: o.label, title: 'not in the ComfyUI sidebar yet: Send to ComfyUI' }));
        set.appendChild(el('a', { class: 'jflow file', href: o.url, target: '_blank', rel: 'noopener', text: 'file', title: 'the workflow file (drag it into the ComfyUI page)' }));
        row.appendChild(set);
      }
      if (unsent) row.appendChild(el('button', { type: 'button', class: 'btn small', text: `Send to ComfyUI (${unsent})`, title: 'save these workflows into the ComfyUI page\'s Workflows sidebar (88fits folder); the links then open them', onclick: async () => {
        const res = await act(j, 'push_workflows', {}, 'sending the workflows to ComfyUI');
        const errs = res && res.ok && res.job && Array.isArray(res.job.push_errors) ? res.job.push_errors : [];
        if (errs.length) App.status(`${title(j)}: ${(res.job.pushed || []).length} sent, ${errs.length} failed: ${errs[0]}`, 'bad', errs.join('\n'));
      } }));
      if (ext === false) row.appendChild(el('span', { class: 'warn-text small', text: 'the ComfyUI page has no 88fits_open extension yet: a link opens the page and the workflow waits in its Workflows sidebar (ask Claude: python tools/comfy.py --install-ext)' }));
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
      } else if (o.type === 'glb' && o.url && typeof Puppet !== 'undefined') {
        // pass 71: the puppet's GLB in the 3D viewer (lazy: a click loads it; destroyed with the card)
        cellEl.classList.add('joutput-glb');
        cellEl.appendChild(Puppet.outputCell(o, holder));
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
    // pass 93 (lane PREVIEW): a driver job's new driver (any output under /dl/drivers/<name>/) opens in the viewer
    const made = Array.from(new Set((j.outputs || []).map((o) => /^\/dl\/drivers\/([A-Za-z0-9_-]+)\//.exec(String(o.url || ''))).filter(Boolean).map((m2) => m2[1])));
    if (made.length && typeof Drivers !== 'undefined') {
      box.appendChild(el('div', { class: 'joutput' }, made.map((nm) => el('button', { type: 'button', class: 'btn small', text: `▶ preview ${nm}`, title: `play ${nm} frame by frame with its frame numbers (the Drivers tab's viewer)`, onclick: () => { Drivers.ensureList(true); Drivers.open(nm, {}); } }))));
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

  /** The words the pipeline will send for a look, composed from methods.json's wordings and the fields (the
   *  authoritative check is asset_job.py --dry-run on the job card). The candidate kinds use candidateWords. */
  function composeWords(m, method, spec, target) {
    const w = (m && Array.isArray(m.ref_wordings)) ? m.ref_wordings : [];
    const r = spec.recipe || {};
    const mid = method ? method.id : spec.method;
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
    // the one picture each method really reads (pass 68, D11): front_from_picture's `ref`, gen_ctl's look_ref
    const picture = mid === 'front_from_picture' ? (spec.job && (spec.job.ref || spec.job.picture)) : mid === 'creature_ctl' ? r.look_ref : null;
    if (!(spec.flags && spec.flags.no_style_ref && mid === 'front_from_picture')) {
      n++;
      const anchor = lookup('style', picture ? 'fixed (with other references)' : 'fixed') || find('style anchor');
      lines.push(`  ${n}. the style anchor (game/art/style/style_anchor.png) — ${anchor ? sub(anchor.text, n) : 'Using exactly the same art style, rendering, shading, palette and outline treatment as the reference image, draw a new subject: <subject>. Do not copy any subject from the reference.'}`);
      if (anchor && anchor.source) lines.push(`     (${anchor.source})`);
    }
    if (picture) {
      n++;
      const row = mid === 'creature_ctl' ? lookup('identity', 'loosely') : lookup('identity', 'closely');
      lines.push(`  ${n}. ${picture} — ${mid === 'creature_ctl' ? 'the look picture (look_ref), followed loosely' : 'your picture, redrawn closely'}`);
      if (row) lines.push(`     ${sub(row.text, n)}${row.source ? ' (' + row.source + ')' : ''}`);
    } else if (mid === 'front_from_picture') lines.push('  (no picture chosen yet: the Reference picture field)');
    if ((spec.refs || []).length) lines.push(`  (${spec.refs.length} reference row${spec.refs.length > 1 ? 's' : ''} from the old form: no tool reads them)`);
    const turn = lookup('view', 'fixed');
    if (turn && mid !== 'front_from_picture' && mid !== 'recolour') { lines.push(`  the other views are turned from the painting — ${sub(turn.text, n + 1)}`); if (turn.source) lines.push(`     (${turn.source})`); }
    const drv = mid === 'creature_pose2' ? r.pose : mid === 'creature_ctl' ? r.drivers : (mid === 'hero_pose5' || mid === 'hero_fit') && r.pose_drivers ? JSON.stringify(r.pose_drivers) : null;
    if (drv) lines.push(`  the clips walk on: ${drv} (OpenPose frames or depth videos steer the clips; a picture never steers motion)`);
    lines.push('');
    lines.push('The subject words:');
    for (const k of ['prompt', 'art_prompt', 'noun', 'keep', 'detail', 'anatomy', 'motion', 'anim_negative', 'back_hint', 'back_prompt', 'dead_hint', 'death', 'stand', 'pose', 'gait', 'directions', 'screen']) if (r[k] != null && r[k] !== '') lines.push(`  ${k}: ${typeof r[k] === 'object' ? JSON.stringify(r[k]) : r[k]}`);
    if (r.words && typeof r.words === 'object') for (const [k, v] of Object.entries(r.words)) lines.push(`  words.${k}: ${v}`);
    if (r.view_hints && typeof r.view_hints === 'object') for (const [k, v] of Object.entries(r.view_hints)) lines.push(`  view_hints.${k}: ${v}`);
    lines.push('');
    if (spec.flags) lines.push(`Flags: ${Object.entries(spec.flags).filter(([, v]) => v).map(([k, v]) => (v === true ? k : `${k}=${v}`)).join(', ') || 'none'}`);
    if (spec.counts) lines.push(`Counts: ${JSON.stringify(spec.counts)}`);
    if (spec.reroll && spec.reroll.mode) lines.push(`Re-roll: ${spec.reroll.mode}${spec.reroll.mode === 'view' && spec.reroll.view ? ' (' + spec.reroll.view + ')' : ''}`);
    lines.push('');
    lines.push(m && m.timings_note ? m.timings_note : '');
    lines.push('What cannot be steered: a picture reaches only the front still (front_from_picture) or the side (gen_ctl\'s look_ref); the other views are edits of that painting; motion comes from the driver or Wan\'s guess; the QA counts subjects, legs and views, never likeness. The authoritative words are what tools/asset_job.py --dry-run records on the job card.');
    return lines.join('\n');
  }

  /** "Show the words" for a badge, title or icon job: the references and the prompt its tool builds from the fields
   *  (empty fields as the server fills them from the defaults). */
  function candidateWordsText(c, jk) {
    const { kind, id, state, contentJson, fixedCode } = c;
    const d = state.defaults && state.defaults.jk === jk ? state.defaults : { fields: {} };
    const eff = Object.assign({}, d.fields || {});
    for (const [k, v] of Object.entries(state.spec.job || {})) if (v != null && v !== '') eff[k] = v;
    const screen = jk === 'icon_cands' ? (eff.screen === 'blue' ? 'blue' : 'green') : (contentJson && String(contentJson.screen || '').toLowerCase() === 'green' ? 'green' : 'blue');
    const lines = [`Method ${jk} · target ${kind} ${id}${fixedCode ? ' ' + fixedCode : ''}`, '', 'References, in the order they are passed (no style anchor for candidates):'];
    lines.push(`  1. ${eff.ref || (jk === 'icon_cands' ? '(none: the words alone)' : '(none: the tool takes the front still)')} — the identity${eff.ref && jk !== 'icon_cands' ? ' ("this exact character")' : ''}${eff.ref && jk === 'icon_cands' ? ', laid on the screen colour' : ''}`);
    if (jk === 'hero_title' && eff.extra_ref) lines.push(`  2. ${eff.extra_ref} — the held object, copied exactly (laid on the screen colour)`);
    lines.push('', 'The prompt:', candidateWords(jk, eff, { screen, creature: kind === 'enemy' || kind === 'boss' }), '');
    lines.push(`${state.spec.counts && state.spec.counts.seeds ? state.spec.counts.seeds : 4} candidates, a seed each (its own: a million apart, moved by this job's id and by every re-run, pass 70); ${jk === 'hero_badge' ? 'the job stops for your pick' : 'Install the one you like from the job card'}.`);
    lines.push('The authoritative words are what tools/asset_job.py --dry-run records on the job card.');
    return lines.join('\n');
  }

  async function openForm(kind, id, o) {
    const opts = o || {};
    const job = opts.job || null;
    if (kind === 'sim' || (job && job.kind === 'sim')) { App.switchTab('sim'); return; }   // pass 77: a sim is set up in its tab
    const mode = opts.mode || (job ? (modeOfMethod({ id: job.method || (job.spec && job.spec.method) || '' })[0] || 'look') : 'look');
    kind = kind || (job && job.target && job.target.kind) || 'enemy';
    id = id || (job && job.target && job.target.id) || '';
    App.status(`opening the job form for ${id}…`, 'busy');
    const [m, drivers, refs, record, specs, content] = await Promise.all([methods(), fetchDrivers(), fetchRefs(), recordFor(kind, id), fetchSpecs(), fetchJson(`/api/content/${encodeURIComponent(kind)}/${encodeURIComponent(id)}`, null)]);
    const contentJson = content && content.json && typeof content.json === 'object' ? content.json : {};
    App.status('', '');
    const all = m.methods || [];
    const list = methodsFor(all, kind, mode);
    const fixedCode = job ? ((job.target && job.target.code) || null) : (opts.code || null);
    // what the form makes (pass 68): a NEW look (+ New look…, or a draft's Generate…: it comes with its candidates, D10),
    // a re-roll of a painted look (the modes of D3), or an edit of a queued job
    const isNewLook = mode === 'look' && !job && !opts.reroll;
    const rerollForm = mode === 'look' && (job ? !!(job.spec && job.spec.reroll && job.spec.reroll.mode) : !!opts.reroll);
    const spec = job && job.spec ? unflatten(job.spec) : {
      method: opts.method || (list[0] && list[0].id) || '', recipe: opts.recipe ? JSON.parse(JSON.stringify(opts.recipe)) : {}, refs: [], drivers: {}, flags: { skip_qa: false, dev: false, seed: 0 },
      counts: { seeds: 3, looks: 1, icon_candidates: isNewLook ? MIN_CANDIDATES : 0, cutout_candidates: isNewLook && kind === 'hero' ? MIN_CANDIDATES : 0 },
      reroll: { mode: opts.reroll ? 'seeds' : '' }, note: opts.note || '', job: {}, refs3d: [],
    };
    if (opts.method) spec.method = opts.method;
    if (!spec.recipe) spec.recipe = {};
    if (!spec.refs) spec.refs = [];
    if (!spec.drivers) spec.drivers = {};
    if (!spec.flags) spec.flags = { skip_qa: false, dev: false, seed: 0 };
    if (!spec.counts) spec.counts = { seeds: 3, looks: 1 };
    if (spec.counts.looks == null) spec.counts.looks = 1;
    if (!spec.reroll) spec.reroll = { mode: '' };
    // a look's recorded painter (Re-roll…, a draft's Generate…): the Model settings start from it; the recipe's own copy
    // is dropped here, since enqueue writes `painter` again from the settings chosen in the form
    if (!spec.job) spec.job = {};
    if (opts.painter && typeof opts.painter === 'object') {
      spec.job.model = opts.painter.model === 'dev' ? 'dev' : 'klein';
      if (opts.painter.steps) spec.job.steps = Number(opts.painter.steps);
      if (opts.painter.guidance) spec.job.guidance = Number(opts.painter.guidance);
      if (opts.painter.turbo === false) spec.job.turbo = false;
      spec.flags.dev = spec.job.model === 'dev';
    }
    if (spec.recipe && spec.recipe.painter) delete spec.recipe.painter;
    // where the look came from: a draft's `from` (Duplicate… makes drafts since pass 68), or the old route (a code from
    // next_codes with the source's recipe: its stills slug and seeds cleared, the source's note starting the new one)
    const duplicateOf = !job && opts.duplicateOf ? String(opts.duplicateOf) : null;
    if (duplicateOf) { delete spec.recipe.stills; delete spec.recipe.seed_offset; if (!spec.note) spec.note = (opts.note ? opts.note + ' · ' : '') + 'from ' + duplicateOf; }
    const fromCode = job ? null : (duplicateOf || (opts.from ? String(opts.from) : null) || (opts.draft && spec.recipe.from ? String(spec.recipe.from) : null));
    const looksOf = record ? (record.looks || record.variants || []) : [];
    // the source's paintings (D5's reuse box): its recipe's stills slug; '' (or absent) = the creature's or the hero's own
    const srcLook = fromCode ? looksOf.find((l) => l.code === fromCode) : null;
    const srcStills = srcLook ? (srcLook.recipe && srcLook.recipe.stills != null ? String(srcLook.recipe.stills) : '') : null;
    const existingCodes = looksOf.map((l) => l.code);
    const state = {
      spec, codes: fixedCode ? [fixedCode] : [], overrides: spec.looks && Array.isArray(spec.looks) ? spec.looks : [], err: '',
      isNew: isNewLook, draft: !!opts.draft && !job, rerollForm, rerollAuto: false, rerollPrev: '',
      recordedPainter: opts.painter && typeof opts.painter === 'object' ? Object.assign({}, opts.painter) : null,
      defaults: null, posted: new Set(),
    };
    if (!list.length && !all.length) spec.method = spec.method || '';

    const dlg = document.createElement('dialog');
    dlg.className = 'sp-modal jform';
    const name = record ? (record.name || id) : id;
    const what = mode === 'look' ? (state.draft ? `generate the draft${fromCode ? ' (made from ' + fromCode + ')' : ''}` : rerollForm ? 're-roll' : duplicateOf ? 'duplicate of ' + duplicateOf : (fixedCode ? 'paint this look' : 'new looks'))
      : mode === 'icon' ? 'icon candidates' : mode === 'badge' ? 'round badge candidates' : mode === 'title' ? 'title cut-out candidates' : 'a 3D driver or reference';
    const headText = job ? `Edit job #${shortId(job.id)} · ${title(job)}` : `Art job · ${kind} ${name}${fixedCode ? ' · ' + fixedCode : ''} · ${what}`;
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

    const c = { kind, id, mode, job, m, all, list, drivers, refs, record, state, existingCodes, fixedCode, queueBtn, err, specs, contentJson, duplicateOf, fromCode, srcStills, dlg };
    c.draw = () => { clear(body); buildForm(body, dlg, c); };
    c.draw();
    queueBtn.addEventListener('click', () => submit(c));
    return dlg;
  }

  function fieldLine(label, control, help) {
    return el('div', { class: 'fieldline' }, el('label', { text: label, title: help || '' }), control, help ? el('div', { class: 'fh', text: help }) : null);
  }

  /** Pass 72 (Garry: "first seed" on every asset that has candidates): the two fields of every candidate job, the
   *  same everywhere: Candidates (spec.counts.seeds, the job's `seeds`) and First seed (spec.job.first_seed, the job's
   *  `first_seed`: tools/cand_seeds.start), under a heading of their own; `what` says what the candidates are. */
  function candidateSeedFields(body, c, jk, what) {
    const spec = c.state.spec;
    if (!spec.job) spec.job = {};
    const f = (c.specs && c.specs[jk] && c.specs[jk].fields) || {};
    const help = (k, dflt) => (f[k] && f[k].help) || dflt;
    body.appendChild(el('h2', {}, 'Candidates', what ? el('small', { text: what }) : null));
    const n = el('input', { type: 'number', class: 'num', min: 1, max: 12, step: 1, value: spec.counts.seeds || (f.seeds && f.seeds.default) || 4 });
    n.addEventListener('change', () => { spec.counts.seeds = Math.max(1, Math.min(12, Math.round(Number(n.value) || 4))); n.value = String(spec.counts.seeds); });
    body.appendChild(fieldLine('Candidates', n, help('seeds', CANDIDATES_HELP)));
    const fs = el('input', { type: 'number', class: 'num', step: 1, value: Number(spec.job.first_seed) || 0 });
    fs.addEventListener('change', () => { const v = Math.round(Number(fs.value) || 0); setKey(spec.job, 'first_seed', v || null); fs.value = String(v); });
    body.appendChild(fieldLine('First seed', fs, help('first_seed', FIRST_SEED_HELP)));
  }

  /** A control for one recipe field of methods.json ({key, type, default, help, options}). */
  /** pass 70: the inherited value goes IN the box (Forms.inheritable): `ctx.inherit` = {value, from}. */
  function inheritIn(inp, value, ctx, onChange, parse, same) {
    return ctx && ctx.inherit && typeof Forms !== 'undefined' && typeof Forms.inheritable === 'function' ? Forms.inheritable(inp, value, ctx, onChange, parse, same) : null;
  }

  function recipeControl(f, value, onChange, ctx) {
    const v = value == null ? '' : value;
    switch (f.type) {
      case 'int': case 'number': {
        const inp = el('input', { type: 'number', class: 'num', value: v, placeholder: f.default != null ? String(f.default) : '', step: f.type === 'int' ? 1 : 'any' });
        const commit = inheritIn(inp, value, ctx, onChange, (t) => Number(t), (t, inh) => t.trim() !== '' && Number(t) === Number(inh));
        inp.addEventListener('change', () => (commit ? commit(inp.value) : onChange(inp.value === '' ? null : Number(inp.value))));
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
        const commit = typeof v === 'object' ? null : inheritIn(ta, value, ctx, onChange, null);
        ta.addEventListener('change', () => (commit ? commit(ta.value) : onChange(ta.value.trim() === '' ? null : ta.value)));
        return ta;
      }
      case 'view_numbers': {
        // pass 70: one number per view ({view: n}; an empty box = the default, or what the asset's own JSON says)
        const views = Array.isArray(f.views) && f.views.length ? f.views : ['front', 'fd', 'side', 'bd', 'back'];
        const obj = v && typeof v === 'object' ? Object.assign({}, v) : {};
        const inhObj = ctx && ctx.inheritObj && typeof ctx.inheritObj === 'object' ? ctx.inheritObj : {};
        const box = el('div', { class: 'viewwords viewnums' });
        for (const view of views) {
          const ph = inhObj[view] != null ? `${inhObj[view]} (the asset's own)` : (f.default != null ? String(f.default) : '');
          const inp = el('input', { type: 'number', class: 'num', value: obj[view] != null ? obj[view] : '', placeholder: ph, step: f.step || 'any', min: f.min != null ? f.min : '', max: f.max != null ? f.max : '' });
          inp.addEventListener('change', () => { if (inp.value.trim() === '') delete obj[view]; else obj[view] = Number(inp.value); onChange(Object.keys(obj).length ? obj : null); });
          box.appendChild(el('label', { class: 'vw' }, el('span', { class: 'muted small', text: view }), inp));
        }
        return box;
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
        // pass 93 (lane PREVIEW): a list of frame numbers picked off its driver's frames (death_keep: methods.json
        // `picker: "frames"`, `frames_of` names the field holding the driver; ctx.recipeValue reads it as it is now)
        if (f.picker === 'frames' && typeof Drivers !== 'undefined') {
          const of = f.frames_of || 'death_drivers';
          return Drivers.keepField({ value, dflt: Array.isArray(f.default) ? f.default : undefined, view: f.view || 'front', label: f.label || f.key,
            getDriver: () => (ctx && typeof ctx.recipeValue === 'function' ? ctx.recipeValue(of) : ''),
            painted: ctx && ctx.painted ? ctx.painted : null, onChange: (l) => onChange(l && l.length ? l : null) });
        }
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
        if (typeof Drivers === 'undefined') { sel.addEventListener('change', () => onChange(sel.value === '' ? null : sel.value)); return sel; }
        // pass 93 (lane PREVIEW): the chosen driver (else the default) plays beside the choice; "preview" opens the viewer
        const view = typeof DriversModel !== 'undefined' ? DriversModel.viewOfKey(f.key) : 'side';
        const box = el('span', { class: 'drv-pickwrap' }, sel);
        let th = Drivers.thumb(v || (f.default != null ? String(f.default) : ''), { view });
        box.appendChild(th);
        sel.addEventListener('change', () => {
          onChange(sel.value === '' ? null : sel.value);
          const next = Drivers.thumb(sel.value || (f.default != null ? String(f.default) : ''), { view });
          th.replaceWith(next);
          th = next;
        });
        return box;
      }
      case 'file': {
        // a picture (2D uploads) or a model (3D uploads) under tools/dl, with an Upload… button; `src` fields are 3D
        const is3d = /^(src|model|fbx|glb)$/.test(f.key || '');
        const sel = el('select');
        sel.appendChild(el('option', { value: '', text: '(none)' }));
        if (!is3d) for (const r of (ctx.refs && ctx.refs['2d']) || []) sel.appendChild(el('option', { value: r.path || r.url || r.name, text: r.name, selected: (r.path || r.url || r.name) === v }));
        for (const u of (ctx.refs && ctx.refs['3d']) || []) { const p = u.path || `tools/dl/uploads/3d/${u.slug}/${u.file || ''}`; /* pass 92: a loose model's own path */ sel.appendChild(el('option', { value: p, text: `${u.slug} (${u.file || 'model'})`, selected: p === v })); }
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
        const commit = typeof v === 'object' ? null : inheritIn(inp, value, ctx, onChange, (t) => t.trim());
        inp.addEventListener('change', () => (commit ? commit(inp.value) : onChange(inp.value.trim() === '' ? null : inp.value.trim())));
        return inp;
      }
    }
  }

  /** pass 70 (the Bandit check): AssetsModel.stillsProblem when it is loaded (the page), else the same rule here (the
   *  self-test's Node harness loads this file alone). */
  function stillsProblem(v) {
    if (typeof AssetsModel !== 'undefined' && typeof AssetsModel.stillsProblem === 'function') return AssetsModel.stillsProblem(v);
    if (v == null || v === '') return '';
    return typeof v === 'string' && /^[A-Za-z0-9_]{0,40}$/.test(v) ? '' : `Stills is a short name for this look's paintings, like bdb; the picture goes in Reference (letters, digits and _ only; got ${JSON.stringify(v)})`;
  }

  function setKey(obj, key, value) { if (value == null || value === '') delete obj[key]; else obj[key] = value; }

  // the fields that hold one picture: shown with a thumbnail, Change… (the library) and Upload… (pass 68)
  const PICTURE_KEYS = ['ref', 'picture', 'look_ref', 'extra_ref', 'title_extra_ref.file'];
  function ptext(p) { return typeof LookGrid !== 'undefined' && typeof LookGrid.painterText === 'function' ? LookGrid.painterText(p) : JSON.stringify(p); }

  function buildForm(body, dlg, c) {
    const { kind, id, mode, job, m, all, list, drivers, refs, record, state, existingCodes, fixedCode, draw, specs, contentJson, fromCode } = c;
    const spec = state.spec;
    const method = all.find((x) => x.id === spec.method) || list[0] || null;
    if (method && spec.method !== method.id) spec.method = method.id;
    const jk = job ? job.kind : jobKind(mode, method, kind);
    const candKind = CAND_KINDS.includes(jk);
    const kindFields = specs && specs[jk] && specs[jk].fields && typeof specs[jk].fields === 'object' ? specs[jk].fields : null;
    const hasField = (k) => (kindFields ? k in kindFields : true);
    // a recipe reaches the tool only through a look job (the other kinds' SPECS have no `recipe`: flatten drops it)
    const takesRecipe = jk === 'look' || !!(kindFields && kindFields.recipe);
    if (candKind && (!state.defaults || state.defaults.jk !== jk)) loadDefaults(c, jk);

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
        el('span', { class: 'muted small', text: ' (each opens in ' }), el('a', { href: COMFY_URL, target: '_blank', rel: 'noopener', text: 'the ComfyUI page' }),
        el('span', { class: 'muted small', text: ' from its Workflows sidebar, 88fits/templates; every job keeps the exact graphs it ran on its card)' }));
      // the templates are saved into the ComfyUI page's sidebar first (once per file), so each link opens the page on it
      if (!S.tplPush || Date.now() - S.tplPushAt > 60000) { S.tplPush = post('/api/workflows/push', {}).catch(() => null); S.tplPushAt = Date.now(); }
      S.tplPush.then((r) => {
        const ext = r && r.extension ? r.extension.installed : null;
        if (r && r.ok && Array.isArray(r.files) && r.files.length) {
          for (const f of r.files) wf.appendChild(el('a', { class: 'jflow' + (f.error ? ' pending' : ' open'), href: f.error ? '/workflows/' + encodeURIComponent(f.name) : f.open_url, target: '_blank', rel: 'noopener', text: f.name.replace(/\.json$/, '') + (f.error ? '' : ' ↗'),
            title: f.error ? `not in the ComfyUI sidebar (${f.error}): the file itself` : (ext === false ? `opens the ComfyUI page; without its 88fits_open extension pick the workflow in the Workflows sidebar: ${f.path}` : `open the ComfyUI page on ${f.path}`) }));
          if (ext === false) wf.appendChild(el('span', { class: 'warn-text small', text: 'the ComfyUI page has no 88fits_open extension yet: a link opens the page and the workflow waits in its Workflows sidebar' }));
          return;
        }
        fetchJson('/api/workflows', null).then((r2) => { for (const f of (r2 && r2.files) || []) wf.appendChild(el('a', { class: 'jflow', href: '/workflows/' + encodeURIComponent(f), target: '_blank', rel: 'noopener', text: f.replace(/\.json$/, '') })); });
      });
      body.appendChild(wf);
      body.appendChild(grid);
    }

    // 2. what to paint: a look's recipe fields (a dotted key is a path into a nested object: pose_drivers.back); a
    // candidate job's own fields filled from the server's defaults (D6); for a kind that reads its words from the JSON, a line
    // pass 71 follow-up: a puppet look's settings (puppet.*, run_fit, fringe_remap) are set in "The 3D puppet" below and
    // recorded in the recipe by the job; Recipe (typed) shows them afterwards
    const fields = (takesRecipe && method && Array.isArray(method.recipe_fields) ? method.recipe_fields : [])
      .filter((f) => !(method && method.id === 'hero_puppet' && (String(f.key).startsWith('puppet.') || f.key === 'run_fit' || f.key === 'fringe_remap')));
    if (candKind) candidateFields(body, c, jk);
    else if (fields.length || mode === 'look') {
      body.appendChild(el('h2', {}, 'What to paint', el('small', { text: 'the recipe the tool reads (written into variants[CODE].recipe for a look job)' })));
      if (!fields.length) body.appendChild(el('p', { class: 'help', text: 'no typed fields for this method in methods.json: the raw recipe below is what the tool gets' }));
      if (fromCode) body.appendChild(sourceBox(c, spec));
      for (const f of fields) {
        if (f.key === 'death' && Array.isArray(m.deaths) && m.deaths.length) { body.appendChild(deathControl(f, m, spec, drivers, draw)); continue; }
        // a recipe keeps only what differs from the creature's own words: an empty field inherits the creature's (shown
        // greyed as the placeholder and marked); `stills` never inherits (an absent key is seeded with the look's letter)
        const own = U.getPath(spec.recipe, f.key);
        const inh = f.key === 'stills' || !contentJson ? undefined : U.getPath(contentJson, f.key);
        const inherited = (own == null || own === '') && inh != null && inh !== '' && typeof inh !== 'object';
        // pass 70: a box type (a text, a hint, a prompt, a number) shows the inherited value IN the box, marked; a choice
        // still names it as its default
        const canInherit = inh != null && inh !== '' && typeof inh !== 'object';
        const inBox = canInherit && !PICTURE_KEYS.includes(f.key) && ['int', 'number', 'textarea', 'text', undefined, '', 'str'].includes(f.type);
        const whoseJ = kind === 'hero' ? 'the hero\'s' : 'the creature\'s';
        const f2 = inherited && !inBox ? Object.assign({}, f, { default: inh }) : f;
        const ctl = PICTURE_KEYS.includes(f.key) ? pictureControl(own, (v) => U.setPath(spec.recipe, f.key, v), { refs, dflt: inherited ? String(inh) : '' })
          : recipeControl(f2, own, (v) => U.setPath(spec.recipe, f.key, v), { drivers, refs, inherit: inBox ? { value: inh, from: `${whoseJ} own ${f.key}` } : null, inheritObj: inh && typeof inh === 'object' ? inh : null,
            // pass 93 (lane PREVIEW): death_keep's picker reads the death driver as the form holds it, and the look's painted death
            recipeValue: (k) => { const ov = U.getPath(spec.recipe, k); return ov != null && ov !== '' ? ov : (contentJson ? U.getPath(contentJson, k) : ''); },
            painted: fixedCode && (kind === 'enemy' || kind === 'boss') ? { enemy: id, code: fixedCode } : null });
        const line = fieldLine(f.label || f.key, ctl, f.help);
        if (inBox) {
          const own0 = !(own == null || own === '');
          const mk = el('span', { class: 'jinh', text: own0 ? `this look's own (${whoseJ} own ${f.key} differs)` : `inherited from ${whoseJ} own ${f.key}: it is in the box; edit it to make it this look's own, empty it to inherit again`, title: String(inh) });
          line.addEventListener('inheritchange', (e) => { mk.textContent = e.detail && e.detail.own ? `this look's own once you leave the box (${whoseJ} own ${f.key} differs)` : `inherited from ${whoseJ} own ${f.key}: it is in the box; edit it to make it this look's own, empty it to inherit again`; });
          line.appendChild(mk);
        }
        if (f.key === 'stills') {
          // pass 70 (the Bandit check): Stills is the look's short name, never the picture (Queue refuses it too)
          const errS = el('div', { class: 'warn-text small jstills-err', text: stillsProblem(own == null || own === '' ? null : own) });
          const inpS = line.querySelector('input');
          if (inpS) inpS.addEventListener('input', () => { errS.textContent = stillsProblem(inpS.value.trim() || null); });
          line.appendChild(errS);
        }
        if (inherited && !inBox) line.appendChild(el('span', { class: 'jinh', text: `inherited: the ${kind === 'hero' ? 'hero' : 'creature'}'s own ${f.key} applies while this is empty`, title: String(inh) }));
        else if (f.key === 'stills' && mode === 'look') line.appendChild(el('span', { class: 'jinh', text: own === '' ? `empty: the ${kind === 'hero' ? 'hero' : 'creature'}'s own paintings are reused` : (own == null ? (state.isNew ? 'left out: new stills are painted under this look\'s own letter' : 'left out: the look keeps the paintings it was made from (the re-roll above decides)') : `the paintings cached under "${own}" are reused`) }));
        else if (f.key === 'seed_offset' && mode === 'look' && (own == null || own === '')) line.appendChild(el('span', { class: 'jinh', text: state.isNew ? 'left out: the server gives a new look seeds of its own from its code' : 'left out: the look keeps its seeds (a re-roll of its stills moves them on)' }));
        body.appendChild(line);
      }
      const raw = el('details', { class: 'jfold' }, el('summary', { text: 'advanced: the raw recipe (JSON)' }));
      const ta = el('textarea', { class: 'mono', spellcheck: false });
      ta.value = JSON.stringify(spec.recipe, null, 2);
      ta.addEventListener('change', () => { try { spec.recipe = JSON.parse(ta.value || '{}'); ta.style.borderColor = ''; draw(); } catch (_) { ta.style.borderColor = 'var(--s8)'; } });
      raw.appendChild(ta);
      body.appendChild(raw);
    } else if (method && Array.isArray(method.recipe_fields) && method.recipe_fields.length) {
      // pass 68: a kind without a recipe reads these words from the asset's own JSON (item_icon's art_prompt)
      body.appendChild(el('h2', {}, 'What to paint'));
      body.appendChild(el('p', { class: 'help', text: `${method.name || method.id} paints from the ${kindClass(kind)}'s own words in its JSON (${method.recipe_fields.map((f) => f.key).join(', ')}): change them in its editor (the Art words), save, then queue this job.` }));
    }

    // 2b. the job's own settings: jobs.py's SPECS for this kind when the server serves them (type, default, required,
    // help, options per field), else methods.json's job_fields; they land in spec.job, and the ones the runner reads as
    // flags / counts are mirrored there too. The keys with controls of their own (method, recipe, refs, drivers, the flags,
    // seed, seeds, note, reroll) are left out, so are a candidate job's fields (in What to paint) and, for a look, the
    // fields only another method's tool reads (D11: front_from_picture's ref / prompt / keep, gen_ctl's picks, recolour)
    const recipeKeys = new Set(fields.map((f) => f.key));
    const candKeys = new Set(candKind ? (CAND_FIELDS[jk] || []).map((f) => f.key) : []);
    const hidden = (k) => (jk === 'look' && METHOD_ONLY[k] && !METHOD_ONLY[k].includes(spec.method)) || candKeys.has(k) || k === 'variant' || k === 'reroll' || k === 'puppet' || k === 'first_seed';
    const specFields = kindFields
      ? Object.entries(kindFields).filter(([k]) => !OWN_KEYS.includes(k) && !recipeKeys.has(k) && !hidden(k)).map(([k, f]) => Object.assign({ key: k }, f || {}, { type: specType(f && f.type) }))
      : null;
    const mfields = (method && Array.isArray(method.job_fields) ? method.job_fields : []).filter((f) => !hidden(f.key));
    const jfields = specFields && specFields.length ? specFields.map((f) => { const mf = mfields.find((x) => x.key === f.key) || {}; return Object.assign({}, mf, f, { help: f.help || mf.help || '' }, mf.type === 'driver' || mf.type === 'file' ? { type: mf.type } : {}); }) : (kindFields ? [] : mfields);   // pass 70: a methods.json `driver` field keeps its library select (driver_tweak's src); pass 92: a `file` field its upload picker (driver_depth's and ref_limbs' src were plain text boxes)
    const modelFields = jfields.filter((f) => f.group === 'model');
    const assetFields = jfields.filter((f) => f.group !== 'model' && f.key !== 'dev');   // `dev` is the old switch: the model select covers it
    if (modelFields.length) {
      // the painter and its quality, apart from what the asset is (Garry: separate the model settings from the asset settings)
      body.appendChild(el('h2', {}, 'Model settings', el('small', { text: 'which painter and how many passes: Flux.2 Klein is quick, Flux.2 dev slower and finer; 0 passes = the default of that painter. The look records them (variants[CODE].recipe.painter): Re-roll… and Generate… start from them' })));
      if (!spec.job) spec.job = {};
      for (const f of modelFields) {
        const cur = spec.job[f.key] != null ? spec.job[f.key] : (f.key === 'model' && spec.flags.dev ? 'dev' : undefined);
        body.appendChild(fieldLine(f.label || f.key, recipeControl(f, cur, (v) => { setKey(spec.job, f.key, v); if (f.key === 'model') spec.flags.dev = v === 'dev'; painterChanged(c); }, { drivers, refs }), f.help));
      }
      if (state.recordedPainter && fixedCode) body.appendChild(el('div', { class: 'jinh', text: `${fixedCode} was painted with ${ptext(state.recordedPainter)}` }));
    }
    if (assetFields.length) {
      body.appendChild(el('h2', {}, 'Asset settings', el('small', { text: specFields && specFields.length ? `what this run makes, apart from the recipe (the ${jk} job's fields as jobs.py validates them)` : 'what this run makes, apart from the recipe' })));
      if (!spec.job) spec.job = {};
      // the continuation fields a pick sets (gen_ctl's --use-side / --view-cands / --use-view, --stage, the pick) live in a fold
      const CONT = ['stage', 'use_side', 'view_cands', 'use_view', 'pick', 'file', 'key'];
      const fold = el('details', { class: 'jfold' }, el('summary', { text: 'continuation fields (the picks set them; leave them for a new job)' }));
      let folded = 0;
      const madeFolds = {};
      const madeFold = (m) => madeFolds[m] || (madeFolds[m] = el('details', { class: 'jfold', open: String(spec.job.mode || '') === m },
        el('summary', { text: m === 'gait' ? 'the made walk (mode gait): swing, lift, flex, duty, bob, sway' : 'the made death on its back (mode flip_curl): roll, curl, bounce, twitch, hold' })));
      for (const f of assetFields) {
        const cur = spec.job[f.key] != null ? spec.job[f.key] : (f.key === 'seeds' ? spec.counts.seeds : (f.key in spec.flags ? spec.flags[f.key] : undefined));
        const onChange = (v) => {
          setKey(spec.job, f.key, v);
          if (f.key === 'seeds') spec.counts.seeds = v == null ? undefined : Number(v);
          if (['dev', 'skip_qa', 'no_video', 'no_style_ref'].includes(f.key)) spec.flags[f.key] = !!v;
          if (f.key === 'seed') spec.flags.seed = Number(v) || 0;
          if (f.key === 'mode') for (const [m, fd] of Object.entries(madeFolds)) fd.open = String(v || '') === m;   // pass 92
        };
        const ctl = PICTURE_KEYS.includes(f.key) ? pictureControl(cur, onChange, { refs }) : recipeControl(f, cur, onChange, { drivers, refs });
        const line = fieldLine(f.label || (f.key === 'ref' ? 'Reference picture' : f.key), ctl, f.help + (f.required ? ' (required)' : ''));
        // pass 92 (lane SPIDER): the made walk's and the made death's settings (driver_depth mode gait / flip_curl) in folds
        // of their own, open when that mode is chosen: 24 more boxes than a clip's driver needs
        const made = /^(gait|flip_curl): /.exec(f.help || '');
        if (made) { const fd = madeFold(made[1]); fd.appendChild(line); continue; }
        if (CONT.includes(f.key) && !(spec.job[f.key])) { fold.appendChild(line); folded++; } else body.appendChild(line);
      }
      for (const fd of Object.values(madeFolds)) body.appendChild(fd);
      if (folded) body.appendChild(fold);
    }

    // pass 71 (lane PLE): the Puppet method's own part (puppet.js): start from, the 3D reference per view, the clips, the walks
    if (spec.method === 'hero_puppet' && typeof Puppet !== 'undefined') Puppet.formSection(body, c);

    // 3. references: where this method's picture goes (pass 68, D11: the old 2D / 3D rows reached no tool)
    referencesNote(body, c, method, jk);

    // 4. what to make: looks, counts
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
          rows.appendChild(lookRow(i, codes[i] || '?', state.overrides[i], method, spec, drivers, refs, fixedCode, state.isNew, contentJson));
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
      if (SEEDED_LOOKS.includes(spec.method)) candidateSeedFields(body, c, jk, spec.method === 'creature_ctl'
        ? 'gen_ctl\'s side view (and any view painted again as candidates) stops for your pick'
        : 'the fronts painted from the picture; you pick one on the job card');
      if (!job) candidateCounts(body, c);
    } else if (mode === 'badge' || mode === 'title' || mode === 'icon') {
      // pass 72: a candidate job's two fields, the same on every kind
      candidateSeedFields(body, c, jk, mode === 'icon' ? 'how many icons to paint and pick from (20 s each; the Flux.2 dev model 4-5 min each)' : 'you pick one on the job card');
    } else {
      body.appendChild(el('h2', {}, 'Counts'));
      const seeds = el('input', { type: 'number', class: 'num', min: 1, max: 12, step: 1, value: spec.counts.seeds || 4 });
      seeds.addEventListener('change', () => { spec.counts.seeds = Number(seeds.value) || 4; });
      body.appendChild(fieldLine(mode === 'driver' ? 'frames / seeds' : 'candidates', seeds, mode === 'icon' ? 'how many icons to paint and pick from (20 s each; the Flux.2 dev model 4-5 min each)' : mode === 'driver' ? 'for a driver: unused (frames are a recipe field)' : 'how many candidates to pick from'));
    }

    // 5. seeds and re-rolls
    if (hasField('seed') || mode === 'look') {
      const seeded = mode === 'look' && SEEDED_LOOKS.includes(spec.method);
      body.appendChild(el('h2', {}, seeded ? 'Re-rolls' : mode === 'look' ? 'Seeds and re-rolls' : 'Seeds'));
      const seed = el('input', { type: 'number', class: 'num', step: 1, value: spec.flags.seed || 0 });
      seed.addEventListener('change', () => { spec.flags.seed = Number(seed.value) || 0; });
      // pass 72: the shift reaches neither gen_ctl nor gen_edit_stills (their candidates start at the First seed above)
      if (seeded) spec.flags.seed = 0;
      else body.appendChild(fieldLine('seed shift', seed, '--seed=N: every still this job paints moves by N × 7919 (0 = none; the same N gives the same pictures again). A new look has seeds of its own anyway (recipe.seed_offset, from its code)'));
      if (mode === 'look') rerollSection(body, c);
    }

    // 6. flags
    const flagRows = [['skip_qa', 'skip the vision QA', 'no LM Studio check of the stills: the first roll is kept (faster; check by eye)']];
    if (!modelFields.length) flagRows.push(['dev', 'Flux.2 dev model', 'the slower, finer model for the stills (205-286 s a still; the server restarts to load it)']);
    const shownFlags = flagRows.filter(([k]) => hasField(k));
    if (shownFlags.length || mode === 'look') {
      body.appendChild(el('h2', {}, 'Flags'));
      const flags = el('div', { class: 'row' });
      for (const [k, label, help] of shownFlags) {
        const cb = el('input', { type: 'checkbox' }); cb.checked = !!spec.flags[k];
        cb.addEventListener('change', () => { spec.flags[k] = cb.checked; });
        flags.appendChild(el('label', { class: 'cb', title: help }, cb, el('span', { text: label })));
      }
      if (shownFlags.length) body.appendChild(fieldLine('options', flags));
    }
    if (hasField('note') || mode === 'look') {
      const note = el('input', { type: 'text', class: 'txt', value: spec.note || '', placeholder: 'why this job (shown on its card)' });
      note.addEventListener('change', () => { spec.note = note.value.trim(); });
      body.appendChild(fieldLine('note', note));
    }

    // 7. the words
    const det = el('details', { class: 'jfold' }, el('summary', { text: 'Show the words that will be sent' }));
    const words = el('pre', { class: 'words' });
    det.addEventListener('toggle', () => {
      if (!det.open) return;
      words.textContent = candKind ? candidateWordsText(c, jk) : (spec.method === 'hero_puppet' && typeof Puppet !== 'undefined' ? Puppet.wordsText(c) + '\n\nThe walks (gen_art, as hero_pose5):\n' : '') + composeWords(m, method, Object.assign({}, spec, { recipe: Object.assign({}, spec.recipe, state.overrides[0] || {}) }), { kind, id, code: fixedCode || (state.codes[0] || ''), art_prompt: contentJson && contentJson.art_prompt });
    });
    det.appendChild(words);
    body.appendChild(det);
  }

  /** The defaults of a candidate job (GET /api/jobs/defaults), once per kind; a new job's empty fields take them (an
   *  edited job keeps its own: the defaults then only tag where a value came from). */
  function loadDefaults(c, jk) {
    const { state, kind, id, fixedCode, job, dlg } = c;
    state.defaults = { jk, loading: true, fields: {}, sources: {} };
    fetchDefaults(jk, kind, id, fixedCode).then((d) => {
      if (!dlg.isConnected || !state.defaults || state.defaults.jk !== jk) return;
      state.defaults = d;
      const sj = state.spec.job || (state.spec.job = {});
      if (!job) for (const f of CAND_FIELDS[jk] || []) { const v = d.fields[f.key]; if (v != null && v !== '' && (sj[f.key] == null || sj[f.key] === '')) sj[f.key] = v; }
      c.draw();
    });
  }

  /** "What to paint" of a badge, title or icon job (D6): Character, Action or Pose, Holds, Camera, the reference picture
   *  and the title's extra reference, filled from the server's defaults, editable, each tagged with where it came from. */
  function candidateFields(body, c, jk) {
    const { state, refs, kind, fixedCode } = c;
    const spec = state.spec;
    if (!spec.job) spec.job = {};
    const d = state.defaults && state.defaults.jk === jk ? state.defaults : null;
    const who = kind === 'hero' ? 'the hero' : (kind === 'enemy' || kind === 'boss') ? 'the creature' : 'the item';
    body.appendChild(el('h2', {}, 'What to paint', el('small', { text: `filled in from ${who}${fixedCode ? ' and its look ' + fixedCode : ''}; change anything: a field left empty is filled the same way when the job is queued` })));
    // where the pick will show in the game (pass 68 review: the default Live title shows no cut-out)
    const shown = jk === 'hero_badge' ? whereShown('badge') : jk === 'hero_title' ? whereShown('cutout') : '';
    if (shown) body.appendChild(el('p', { class: 'help jwhere', text: `Where the pick shows: ${shown}.` }));
    if (!d || d.loading) body.appendChild(el('p', { class: 'help', text: 'reading the defaults…' }));
    else if (d.error) body.appendChild(el('p', { class: 'help warn-text', text: `no defaults from the server (${d.error}): empty fields fall back to the tool's own (the hero's portrait_prompt and title words, the base front still)` }));
    for (const f of CAND_FIELDS[jk] || []) {
      const dv = d && d.fields ? d.fields[f.key] : undefined;
      const tag = el('span', { class: 'jsrc' });
      const retag = () => { tag.textContent = sourceTag(f.key, spec.job[f.key], d); tag.classList.toggle('mine', tag.textContent.startsWith('yours')); };
      const onChange = (v) => { setKey(spec.job, f.key, v); retag(); };
      const ctl = f.type === 'picture'
        ? pictureControl(spec.job[f.key], onChange, { refs, dflt: dv != null ? String(dv) : '', dfltUrl: f.key === 'ref' && d ? d.ref_url : null, dfltExists: f.key === 'ref' && d ? d.ref_exists : null })
        : recipeControl(Object.assign({}, f, { default: dv != null && dv !== '' ? String(dv) : undefined }), spec.job[f.key], onChange, { refs });
      const line = fieldLine(f.label, ctl, f.help);
      line.appendChild(tag);
      retag();
      body.appendChild(line);
    }
  }

  /** A picture field (pass 68, D6/D11): the thumbnail (click to zoom), the path (editable: repo-relative, tools/dl-relative
   *  or absolute), Change… (the picture library), Upload… (a new picture under tools/dl/uploads/2d/) and back to the
   *  default. o = {refs, dflt, dfltUrl, dfltExists}. */
  function pictureControl(value, onChange, o) {
    const ctx = o || {};
    let cur = value == null ? '' : String(value);
    const thumb = el('div', { class: 'jpic-thumb' });
    const inp = el('input', { type: 'text', class: 'txt', value: cur, spellcheck: false, placeholder: ctx.dflt ? `empty: ${ctx.dflt}` : '(no picture)' });
    const note = el('div', { class: 'jpic-note small' });
    const back = el('button', { type: 'button', class: 'btn small ghost', text: '↺ default', title: ctx.dflt ? `back to ${ctx.dflt}` : '' });
    const paint = () => {
      clear(thumb);
      note.textContent = '';
      note.classList.remove('warn-text');
      const isDefault = !!ctx.dflt && cur === String(ctx.dflt);
      const url = isDefault && ctx.dfltUrl ? ctx.dfltUrl : refUrl(cur);
      if (!cur) thumb.appendChild(el('span', { class: 'muted small', text: 'no picture' }));
      else if (url) {
        const img = el('img', { src: url, alt: '', title: `${cur} (click to zoom)` });
        img.addEventListener('click', () => { if (typeof StripPlayer !== 'undefined') StripPlayer.openImage(url, cur); });
        img.addEventListener('error', () => { img.replaceWith(el('span', { class: 'muted small', text: 'no preview (not on disk?)' })); });
        thumb.appendChild(img);
      } else thumb.appendChild(el('span', { class: 'muted small', text: 'no preview: the page shows pictures under tools/dl' }));
      if (isDefault && ctx.dfltExists === false) { note.textContent = 'not painted yet: no such file on disk. A job queued behind the look\'s own job finds it; else pick another picture.'; note.classList.add('warn-text'); }
      back.hidden = !ctx.dflt || isDefault;
    };
    const set = (v) => { cur = v == null ? '' : String(v).trim(); inp.value = cur; onChange(cur || null); paint(); };
    inp.addEventListener('change', () => set(inp.value));
    back.addEventListener('click', () => set(ctx.dflt));
    const up = el('input', { type: 'file', accept: '.png,.jpg,.jpeg,.webp', style: 'display:none' });
    up.addEventListener('change', async () => {
      const f = up.files && up.files[0];
      if (!f) return;
      App.status(`uploading ${f.name}…`, 'busy');
      const res = await upload(f, '2d');
      if (!res.ok) { App.status(`upload failed: ${res.error}`, 'bad'); return; }
      App.status(`uploaded ${f.name} as ${res.path}`, 'good');
      set(res.path || res.url);
      fetchRefs();
    });
    const change = el('button', { type: 'button', class: 'btn small', text: 'Change…', title: 'pick a picture from the library: the uploads (tools/dl/uploads/2d) and the 3D models\' renders', onclick: () => pickPicture(S.refs || ctx.refs, cur, (p) => set(p)) });
    const wrap = el('div', { class: 'jpic' }, thumb, el('div', { class: 'jpic-side' }, inp, el('div', { class: 'row' }, change, el('button', { type: 'button', class: 'btn small', text: 'Upload…', title: 'a picture from this computer: saved under tools/dl/uploads/2d/', onclick: () => up.click() }), back, up), note));
    paint();
    return wrap;
  }

  /** The picture library: the 2D uploads and the 3D models' renders as thumbnails; a click picks one. */
  function pickPicture(refs, current, pick) {
    const items = [];
    for (const r of (refs && refs['2d']) || []) items.push({ path: r.path || `tools/dl/uploads/2d/${r.name}`, url: r.url || refUrl(r.path), label: r.name, group: 'Pictures (tools/dl/uploads/2d)' });
    for (const u of (refs && refs['3d']) || []) for (const url of u.renders || []) items.push({ path: 'tools/dl/' + String(url).replace(/^\/dl\//, ''), url, label: `${u.slug} · ${String(url).split('/').pop()}`, group: '3D models\' renders (tools/dl/uploads/3d)' });
    const dlg = document.createElement('dialog');
    dlg.className = 'sp-modal';
    const grid = el('div', { class: 'jpicgrid' });
    let group = '';
    for (const it of items) {
      if (it.group !== group) { group = it.group; grid.appendChild(el('div', { class: 'jpicgroup', text: group })); }
      grid.appendChild(el('div', { class: 'jpiccard' + (it.path === current ? ' on' : ''), title: it.path, onclick: () => { pick(it.path); dlg.close(); } },
        el('img', { src: it.url, alt: '', loading: 'lazy' }), el('span', { text: it.label })));
    }
    if (!items.length) grid.appendChild(el('div', { class: 'muted', text: 'no pictures yet: Upload… beside the field adds one (tools/dl/uploads/2d/)' }));
    const filter = el('input', { type: 'search', class: 'txt', placeholder: 'filter…' });
    filter.addEventListener('input', () => { const f = filter.value.toLowerCase(); for (const x of grid.querySelectorAll('.jpiccard')) x.hidden = !!f && !x.title.toLowerCase().includes(f) && !x.textContent.toLowerCase().includes(f); });
    dlg.append(el('div', { class: 'sp-modal-head' }, el('b', { text: `the picture library · ${items.length}` }), el('span', { class: 'muted small', text: 'click a picture to use it' }), filter, el('span', { class: 'spacer' }), el('button', { type: 'button', class: 'btn small', text: '✕', onclick: () => dlg.close() })), grid);
    document.body.appendChild(dlg);
    dlg.addEventListener('close', () => dlg.remove());
    dlg.showModal();
  }

  /** A draft's (or a duplicate's) source: what is copied, and for a still method the box that reuses its paintings. */
  function sourceBox(c, spec) {
    const { fromCode, srcStills, state, draw, kind } = c;
    const still = STILL_METHODS.includes(spec.method);
    const own = kind === 'hero' ? 'hero' : 'creature';
    const what = spec.method === 'hero_fit' ? 'hero_fit walks the hero\'s own paintings (its still_keys): nothing new is painted, only the walks are made again.'
      : still ? 'Its stills are painted fresh under its own letter and its own seeds, so the Model settings below apply to them.' : '';
    const box = el('div', { class: 'jdup' }, el('div', {}, el('b', { text: state.draft ? `A draft made from ${fromCode}` : `Duplicate of ${fromCode}` }),
      el('span', { text: `: ${state.draft ? 'its recipe (copied from ' + fromCode + ', then yours to change) is below' : 'its recipe, words and painter are filled in below and the new look gets the next free code'}. ${what}` })));
    if (still && srcStills != null) {
      const want = String(srcStills);
      const cb = el('input', { type: 'checkbox' }); cb.checked = spec.recipe.stills != null && String(spec.recipe.stills) === want;
      cb.addEventListener('change', () => { if (cb.checked) spec.recipe.stills = want; else delete spec.recipe.stills; draw(); });
      box.appendChild(el('label', { class: 'cb', title: want ? `recipe.stills = "${want}": the paintings cached under that slug are reused` : `recipe.stills = "": the ${own}'s own paintings are reused (an absent key makes the job paint new stills)` },
        cb, el('span', { text: `reuse ${fromCode}'s paintings: only the clips are made again, with this look's own seeds (the Model settings then change nothing)` })));
    }
    const sk = spec.recipe && spec.recipe.still_keys && typeof spec.recipe.still_keys === 'object' ? Object.keys(spec.recipe.still_keys) : [];
    if (sk.length) box.appendChild(el('div', { class: 'muted small', text: `its still_keys name ${sk.join(', ')}: those views come from the stills named there, whatever the box says` }));
    return box;
  }

  /** Where the method's picture goes (pass 68, D11): the 2D / 3D reference rows of the old form reached no tool, so each
   *  method says what it reads instead; an old job's rows are named, kept, and said to be unread. */
  function referencesNote(body, c, method, jk) {
    const { state, all, mode } = c;
    const spec = state.spec;
    const mid = method ? method.id : spec.method;
    const ffp = all.find((x) => x.id === 'front_from_picture');
    let text;
    if (CAND_KINDS.includes(jk)) text = 'The reference picture is the field above: one picture, the identity the candidates keep (no style anchor). The title\'s extra reference, when set, is the held object.';
    else if (mid === 'front_from_picture') text = 'The picture is the Reference picture field above, the only picture this method reads (after the style anchor, unless "no style anchor" is ticked).';
    else if (mid === 'creature_ctl') text = 'gen_ctl reads its picture from look_ref and its motion from drivers, both in What to paint above: nothing else reaches it.';
    else if (mid === 'hero_puppet') text = 'The 3D reference rows above are the pictures the shape is made from (painted arms-out, a look\'s still or an uploaded picture). The walks are Wan clips of the look\'s stills on the puppet\'s own guides: no other picture is passed. A badge or a title cut-out takes a picture (their own forms).';
    else if (mid === 'hero_pose5' || mid === 'hero_fit') text = 'Hero looks paint from words (art_prompt and the hints) with the style anchor, and walk on the pose drivers (pose_drivers above): no picture is passed to them. A badge or a title cut-out takes a picture (their own forms).';
    else if (mid === 'recolour') text = 'A recolour reads its source look\'s strip and icon: no picture.';
    else if (jk === 'look') text = `This method paints from words: to start from a picture, use "${ffp ? ffp.name || ffp.id : 'front_from_picture'}" first, then paint the look with its stills slug.`;
    else if (mode === 'driver') text = 'The model is the src field above: an upload (tools/dl/uploads/3d/) or a Mixamo FBX.';
    else text = 'This job takes no picture.';
    body.appendChild(el('h2', {}, 'References', el('small', { text: 'what the painter is shown besides the words' })));
    body.appendChild(el('p', { class: 'help', text }));
    if (mid === 'front_from_picture' && jk === 'look') {
      const cb = el('input', { type: 'checkbox' }); cb.checked = !!spec.flags.no_style_ref;
      cb.addEventListener('change', () => { spec.flags.no_style_ref = cb.checked; });
      body.appendChild(el('label', { class: 'cb', title: 'drop the style anchor: the picture is the only reference (gen_edit_stills --no-style-ref)' }, cb, el('span', { text: 'no style anchor' })));
    }
    const rows = (spec.refs || []).length, d3 = Object.keys(spec.drivers || {}).length;
    if (rows || d3) body.appendChild(el('p', { class: 'help warn-text', text: `this job carries ${rows ? rows + ' reference row' + (rows > 1 ? 's' : '') : ''}${rows && d3 ? ' and ' : ''}${d3 ? 'drivers ' + JSON.stringify(spec.drivers) : ''} from the old form: no tool reads them (kept as they are)` }));
  }

  /** The candidates a NEW look comes with (D10): counts of at least MIN_CANDIDATES, required (Queue refuses fewer); on a
   *  re-roll the same counts are optional extras (0 = none). */
  function candidateCounts(body, c) {
    const { kind, state } = c;
    const spec = state.spec;
    const plan = candidatePlan(kind, spec.method);
    if (!plan.length) {
      if (kind === 'hero' || kind === 'enemy' || kind === 'boss') body.appendChild(el('p', { class: 'help', text: spec.method === 'recolour' ? 'A recolour recolours its source\'s icon too: no candidates come with it.' : 'A front from a picture paints no look yet: the candidates come with the look painted from it.' }));
      return;
    }
    body.appendChild(el('h3', { class: 'jsub', text: state.isNew ? `Candidates: required, at least ${MIN_CANDIDATES} of each` : 'Candidates: optional on a re-roll (0 = none)' }));
    for (const p of plan) {
      if (spec.counts[p.count] == null) spec.counts[p.count] = state.isNew ? MIN_CANDIDATES : 0;
      const inp = el('input', { type: 'number', class: 'num', min: state.isNew ? MIN_CANDIDATES : 0, max: 12, step: 1, value: spec.counts[p.count] });
      inp.addEventListener('change', () => { const v = Math.max(0, Math.min(12, Math.round(Number(inp.value) || 0))); spec.counts[p.count] = v; inp.value = String(v); });
      body.appendChild(fieldLine(p.label, inp, candidateHelp(p, state.isNew)));
    }
    // pass 72: their first seed (each candidate job takes it as its own First seed)
    const fs = el('input', { type: 'number', class: 'num', step: 1, value: Number(spec.counts.first_seed) || 0 });
    fs.addEventListener('change', () => { spec.counts.first_seed = Math.round(Number(fs.value) || 0); fs.value = String(spec.counts.first_seed); });
    body.appendChild(fieldLine('First seed', fs, `${FIRST_SEED_HELP} (for the ${plan.map((p) => p.label).join(' and the ')} above)`));
    if (spec.method === 'creature_ctl' && state.isNew) body.appendChild(el('p', { class: 'help warn-text', text: 'gen_ctl stops for your pick of the side, and the comfy lane runs the next job while it waits: the icon candidates may paint before this look\'s front still exists (then from the words alone). Re-queue them from the Jobs tab once the look is done if they miss it.' }));
  }
  function candidateHelp(p, isNew) {
    const req = isNew ? `required on a new look: at least ${MIN_CANDIDATES}. ` : 'optional: 0 = none. ';
    if (p.jk === 'icon_cands') return req + 'A job of its own, queued after the look on the comfy lane with the same Model settings: the creature\'s words and the new look\'s front still as the reference (the server fills them in). Install the one you like from its card: it becomes <id>_icon_<letter>.png, the look\'s own icon.';
    if (p.jk === 'hero_badge') return req + `Round badge candidates, a job of its own after the look with the same Model settings: the hero's words and the new look's front still as the reference. The pick becomes the look's own round icon (variants[CODE].icon)${whereShown('badge') ? ': ' + whereShown('badge') : ''}.`;
    return req + `Title cut-out candidates (660 × 888), a job of its own after the look with the same Model settings: the hero's words, the title pose and the new look's front still as the reference. The pick becomes the look's own cut-out (art/ui/wanted/hero_<id>_<letter>.png, variants[CODE].title)${whereShown('cutout') ? ': ' + whereShown('cutout') : ''}.`;
  }
  /** Where the game shows a hero look's badge or cut-out (LookGrid.WHERE_SHOWN, looks.js): the cut-out only on the
   *  Painted title, a debug choice; the default Live title draws the strip. */
  function whereShown(k) { return typeof LookGrid !== 'undefined' && LookGrid.WHERE_SHOWN && LookGrid.WHERE_SHOWN[k] ? LookGrid.WHERE_SHOWN[k] : ''; }

  /** The re-roll modes (D3) of a re-roll form; a new look has nothing of its own to throw away. When the Model settings
   *  stop matching the look's recorded painter, "repaint the stills" is selected (a painter paints only stills). */
  function rerollSection(body, c) {
    const { state, draw, fixedCode } = c;
    const spec = state.spec;
    if (!state.rerollForm) {
      body.appendChild(fieldLine('re-roll', el('span', { class: 'muted small', text: state.isNew ? 'a new look: nothing of its own is cached yet, so there is nothing to re-roll' : 'none: the cached stills and clips are reused' })));
      return;
    }
    const allowed = rerollModes(spec.method);
    if (!allowed.length) {
      spec.reroll.mode = '';
      body.appendChild(fieldLine('re-roll', el('span', { class: 'muted small', text: spec.method === 'recolour' ? 'a recolour keeps nothing cached: it simply runs again' : spec.method === 'front_from_picture' ? 'a front from a picture paints new candidates on every run (a re-run moves its seeds on; the First seed above starts them)' : 'nothing to re-roll for this method' })));
      return;
    }
    const modes = [{ v: '', label: 'none (cached work reused)', help: 'the stills and clips already on disk are reused: only what is missing is made' }].concat(REROLL.filter((r) => allowed.includes(r.v)));
    if (spec.reroll.mode && !allowed.includes(spec.reroll.mode)) spec.reroll.mode = allowed[0];
    if (REROLL_FOR[spec.method]) body.appendChild(el('div', { class: 'muted small', text: spec.method === 'hero_fit' ? 'hero_fit walks the hero\'s own paintings, which every look shares: only its clips can be made again (paint stills of its own with hero_pose5)' : spec.method === 'creature_ctl' ? 'gen_ctl paints its stills from the picked side with its code\'s own seeds: re-roll a view or the clips (new side candidates: a new look)' : 'creature_proc has no clips: its frames are procedural' }));
    const rr = el('div', { class: 'row' });
    for (const r of modes) {
      const rb = el('input', { type: 'radio', name: 'reroll' }); rb.checked = (spec.reroll.mode || '') === r.v;
      rb.addEventListener('change', () => { spec.reroll.mode = r.v; state.rerollAuto = false; draw(); });
      rr.appendChild(el('label', { class: 'cb', title: r.help }, rb, el('span', { text: r.label })));
    }
    const cur = modes.find((r) => r.v === (spec.reroll.mode || '')) || modes[0];
    body.appendChild(fieldLine('re-roll', rr, `what the job throws away before it paints (the server does it when the job is queued): ${cur.help}`));
    if (spec.reroll.mode === 'stage') {
      // pass 71: the puppet stage the job starts from again
      const ss = el('select');
      if (!spec.reroll.stage) spec.reroll.stage = 'guides';
      for (const st of ['apose', 'shape', 'rig', 'anim', 'guides']) ss.appendChild(el('option', { value: st, text: st, selected: spec.reroll.stage === st }));
      ss.addEventListener('change', () => { spec.reroll.stage = ss.value; });
      body.appendChild(fieldLine('the stage', ss, 'apose = new arms-out paintings (and everything after); shape = a new Hunyuan3D shape from the same paintings; rig = the joints found again; anim = the clips and the colours again; guides = new guides (a new folder) from the same GLB'));
    }
    if (spec.reroll.mode === 'view' || spec.reroll.mode === 'clip') {
      const vs = el('select');
      if (!spec.reroll.view) spec.reroll.view = spec.reroll.mode === 'clip' ? 'side' : 'front';
      for (const v of ['front', 'fd', 'side', 'bd', 'back']) vs.appendChild(el('option', { value: v, text: v, selected: spec.reroll.view === v }));
      vs.addEventListener('change', () => { spec.reroll.view = vs.value; });
      body.appendChild(fieldLine('the view', vs, spec.reroll.mode === 'clip'
        ? 'the view walked again: change its driver first in What to paint (pose_drivers.<view> for a hero, drivers for gen_ctl) when another driver is the fix'
        : 'gen_ctl --view-cands=<view>: candidates of that one view to pick from'));
    }
    const rp = state.recordedPainter;
    if (rp && painterDiffers(painterOfSpec(spec), rp)) {
      body.appendChild(el('div', { class: 'jnote', text: allowed.includes('stills')
        ? `The Model settings differ from the painter ${fixedCode || 'this look'} was painted with (${ptext(rp)}). A painter only paints stills, so "repaint the stills" ${spec.reroll.mode === 'stills' ? 'is selected' : 'is what lets the new settings show'}; the walks are then made again from the new stills.`
        : `The Model settings differ from the painter ${fixedCode || 'this look'} was painted with (${ptext(rp)}), but this method's re-roll paints no stills: the new settings change nothing here. To paint with them, Duplicate… the look and Generate… the draft.` }));
    }
    if (rp && rp.stills === 'reused') body.appendChild(el('div', { class: 'jnote', text: `${fixedCode || 'This look'}'s recorded painter painted none of its stills: they were reused from earlier paintings.` }));
  }
  /** D3: a re-roll whose Model settings stop matching the recorded painter selects "repaint the stills" (once; the
   *  mode chosen before comes back when the settings match again and nobody touched the radios). */
  function painterChanged(c) {
    const { state } = c;
    const spec = state.spec;
    if (!state.rerollForm || !state.recordedPainter) return;
    if (!rerollModes(spec.method).includes('stills')) { c.draw(); return; }
    const differs = painterDiffers(painterOfSpec(spec), state.recordedPainter);
    if (differs && !state.rerollAuto && spec.reroll.mode !== 'stills') { state.rerollPrev = spec.reroll.mode || ''; spec.reroll.mode = 'stills'; state.rerollAuto = true; c.draw(); }
    else if (!differs && state.rerollAuto) { if (spec.reroll.mode === 'stills') spec.reroll.mode = state.rerollPrev; state.rerollAuto = false; c.draw(); }
    else c.draw();
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

  /** pass 92 (lane SPIDER): the probe's leg chains (probe.limbs) in words: the count every painter copies (Garry's spider
   *  had six legs and nothing said so), and that a legged rig walks and dies without a clip (driver_depth gait / flip_curl). */
  function limbsText(p, arm, acts) {
    const l = p && p.limbs;
    if (!arm || !l || !(l.count >= 2) || p.humanoid) return '';
    let t = ` · ${l.count} leg chains (${l.left} left, ${l.right} right)`;
    if (l.left !== l.right) t += ': the sides differ, check the bones';
    t += acts.length ? '; no walk among the clips? driver_depth mode gait makes one, mode flip_curl a death on its back' : '; driver_depth mode gait makes a walk without a clip, mode flip_curl a death on its back';
    t += '; a missing leg pair is copied by "A model\'s legs fixed" (ref_limbs)';
    return t;
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
    else if (arm && !acts.length && p.limbs && p.limbs.count >= 2 && !p.humanoid) text = 'This model has no animation clip; it can be the icon\'s reference and the look reference';   // pass 92: limbsText says how it walks
    else if (!arm || !acts.length) text = 'This model has no animation clip, so it cannot drive a walk; it can be the icon\'s reference and the look reference. For a walk export it from Mixamo as FBX Binary, 30 fps, In Place, keyframe reduction none, or a GLB that carries its animation.';
    else if (p.rig_guess === 'mixamo') text = `Mixamo-style humanoid with ${acts.length} clip${acts.length > 1 ? 's' : ''} (${acts.map((a) => a.name + (a.seconds ? ' ' + a.seconds.toFixed(1) + ' s' : '')).join(', ')}): OpenPose drivers (24 frames for a run, 12 for a walk; loop or one-shot) and depth drivers.`;
    else if (p.rig_guess === 'sm') text = `A Synty-style (Bone_SM_*) humanoid with ${acts.length} clip${acts.length > 1 ? 's' : ''}: OpenPose drivers with rig=sm, and depth drivers.`;
    else text = `A rigged model (${p.rig_guess || 'other'} rig) with ${acts.length} clip${acts.length > 1 ? 's' : ''}: depth drivers of its own motion (pick the walk / death / idle clip); for OpenPose drivers a bone map is needed (ask Claude).`;
    // pass 92 (lane SPIDER): the leg count the painters will copy, and the made motions a legged rig gets without a clip
    text += limbsText(p, arm, acts);
    if (u.loose && !u.probe) text = 'put in uploads/3d by hand: queue "What a 3D file can do" on it to probe it. ' + text;
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
      // pass 93 (lane PREVIEW): the full viewer (every view, the frame numbers) without picking the card
      if (typeof Drivers !== 'undefined') card.appendChild(el('button', { type: 'button', class: 'btn small', text: 'preview', title: `${d.name}: every view frame by frame with its numbers`, onclick: (e) => { e.stopPropagation(); Drivers.open(d.name, { view }); } }));
      grid.appendChild(card);
    }
    const filter = el('input', { type: 'search', class: 'txt', placeholder: 'filter…' });
    filter.addEventListener('input', () => { const f = filter.value.toLowerCase(); for (const c of grid.children) c.hidden = f && !c.textContent.toLowerCase().includes(f); });
    dlg.append(el('div', { class: 'sp-modal-head' }, el('b', { text: `the driver library · ${drivers.length}` }), el('span', { class: 'muted small', text: 'hover a card to play its frames; click to pick' }), filter, el('span', { class: 'spacer' }), el('button', { type: 'button', class: 'btn small', text: '✕', onclick: () => dlg.close() })), grid);
    document.body.appendChild(dlg);
    dlg.addEventListener('close', () => { for (const p of players) p.destroy(); dlg.remove(); });
    dlg.showModal();
  }

  /** The per-look overrides a method's tool reads (pass 68: the old rows wrote `prompt` for every method, which gen_art
   *  never reads, `seed`, which nothing read, and a driver no look tool took). */
  function lookRowKeys(mid, isNew) {
    const ctl = mid === 'creature_ctl';
    const paints = !['recolour', 'front_from_picture', 'hero_fit'].includes(mid);
    const moves = !['recolour', 'front_from_picture'].includes(mid);
    const out = [];
    if (paints) out.push(ctl ? { key: 'prompt', type: 'textarea', help: 'this look\'s subject words for gen_ctl (else the shared recipe\'s)' } : { key: 'art_prompt', type: 'textarea', help: 'this look\'s subject words (else the shared recipe\'s, else the JSON\'s art_prompt)' });
    if (ctl) out.push({ key: 'keep', type: 'text', help: 'what every view keeps (gen_ctl keep)' }, { key: 'detail', type: 'text', help: 'the finish words (gen_ctl detail)' });
    if (moves) out.push({ key: 'motion', type: 'textarea', help: 'how it moves, for the clips' }, { key: 'anim_negative', type: 'text', help: 'what the clips must not do' });
    if (isNew && mid !== 'recolour') out.push({ key: 'seed_offset', type: 'int', help: 'this look\'s own seeds: every seed it paints moves by N × 104729 (empty = one the server derives from its code, so looks queued together never come out as clones)' });
    if (paints) out.push({ key: 'screen', type: 'select', options: ['green', 'blue'], help: 'the keying screen (blue for a green creature)' });
    if (['creature_free2', 'creature_free8', 'creature_pose2', 'creature_proc', 'creature_ctl'].includes(mid)) out.push({ key: 'directions', type: 'select', options: ['2', '8'], help: '2 = front and back; 8 = side and three-quarter views too' });
    return out;
  }

  function lookRow(i, code, ov, method, spec, drivers, refs, fixed, isNew, contentJson) {
    const mid = method ? method.id : spec.method;
    const det = el('details', { class: 'lookrow', open: i === 0 && fixed });
    const n = Object.keys(ov).length;
    const sum = el('summary', {}, el('b', { text: `Look ${i + 1}` }), el('span', { class: 'muted', text: fixed ? '' : 'will become' }), el('code', { text: code }), el('span', { class: 'muted small', text: n ? `${n} override${n > 1 ? 's' : ''}` : 'no overrides: the shared recipe' }));
    det.appendChild(sum);
    for (const f of lookRowKeys(mid, isNew)) {
      // pass 70: what this look would get without an override (the shared recipe's, else the asset's own) is in the box
      const shared = spec.recipe ? U.getPath(spec.recipe, f.key) : undefined;
      const own = contentJson ? U.getPath(contentJson, f.key) : undefined;
      const inh = shared != null && shared !== '' ? shared : own;
      const boxed = ['text', 'textarea', 'int', 'number'].includes(f.type) && inh != null && inh !== '' && typeof inh !== 'object';
      det.appendChild(fieldLine(f.key, recipeControl(f, ov[f.key], (v) => { setKey(ov, f.key, v); }, { drivers, refs, inherit: boxed ? { value: inh, from: shared != null && shared !== '' ? 'the shared recipe above' : 'the words of the asset itself' } : null }), f.help + (boxed ? ' · inherited in the box: edit it to give this look its own' : '')));
    }
    // the walk of this look alone: the recipe key its tool reads (a creature's pose driver, gen_ctl's depth driver)
    const drvKey = mid === 'creature_pose2' ? 'pose' : mid === 'creature_ctl' ? 'drivers' : null;
    if (drvKey) {
      const depth = drvKey === 'drivers';
      const drv = el('select');
      drv.appendChild(el('option', { value: '', text: '(the shared recipe\'s)' }));
      for (const d of drivers.filter((x) => depth === (x.kind === 'depth'))) drv.appendChild(el('option', { value: d.name, text: `${d.name} (${d.kind || 'pose'})`, selected: d.name === (ov[drvKey] || ov.driver) }));
      drv.addEventListener('change', () => { delete ov.driver; setKey(ov, drvKey, drv.value); });
      det.appendChild(fieldLine(depth ? 'depth driver' : 'pose driver', drv, depth ? 'this look walks on another depth driver (recipe.drivers)' : 'this look walks on another OpenPose driver (recipe.pose)'));
    }
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

  /** A candidate job's spec as a new look queues it (D10): the count, the look's Model settings, and no words (the server
   *  fills them from the defaults: the character, the action or pose, the new look's front still as the reference). */
  function candidateSpec(p, n, spec, specs) {
    const pj = painterOfSpec(spec);
    const job = { model: pj.model };
    if (pj.steps) job.steps = pj.steps;
    if (spec.counts && Number(spec.counts.first_seed)) job.first_seed = Math.round(Number(spec.counts.first_seed));   // pass 72
    if (pj.model === 'dev') { if (pj.guidance) job.guidance = pj.guidance; job.turbo = pj.turbo; }
    return flatten({ method: p.jk, recipe: {}, refs: [], drivers: {}, flags: { dev: pj.model === 'dev', skip_qa: !!(spec.flags && spec.flags.skip_qa) }, counts: { seeds: n }, job, note: '' }, p.jk, specs);
  }

  async function submit(c) {
    const { kind, id, mode, job, all, state, fixedCode, dlg, err, queueBtn, record, existingCodes, specs } = c;
    const spec = state.spec;
    const method = all.find((x) => x.id === spec.method) || null;
    if (!spec.method) { err.textContent = 'pick a method'; return; }
    // pass 70 (the Bandit check): Stills is the look's short name; the picture goes in Reference
    const stillsWhy = stillsProblem(spec.recipe && spec.recipe.stills != null && spec.recipe.stills !== '' ? spec.recipe.stills : null)
      || stillsProblem(spec.stills != null && spec.stills !== '' ? spec.stills : null);
    if (stillsWhy) { err.textContent = stillsWhy; return; }
    const jk = job ? job.kind : jobKind(mode, method, kind);
    const base = Object.assign({}, spec);
    delete base.looks;
    delete base.refs3d;
    const name = record ? (record.name || id) : id;
    // a new look comes with its candidates (D10): Queue refuses fewer than the minimum
    const plan = mode === 'look' && !job ? candidatePlan(kind, spec.method) : [];
    if (state.isNew) { const why = candidateRefusal(plan, spec.counts); if (why) { err.textContent = why; return; } }
    queueBtn.disabled = true;
    err.textContent = '';
    try {
      if (job) {
        const one = Object.assign({}, base, { recipe: Object.assign({}, base.recipe, state.overrides[0] || {}) });
        // a candidate field cleared here goes out as '' so the server fills it again from the defaults (withClearedFields)
        const res = await post(`/api/jobs/${encodeURIComponent(job.id)}`, { spec: withClearedFields(job.kind, flatten(one, job.kind, specs)), title: job.title });
        if (!res.ok) { err.textContent = res.error; return; }
        toast(`job #${shortId(job.id)} changed`);
        dlg.close(); await poll(); return;
      }
      if (mode !== 'look') {
        // one job: icon / badge / title candidates, an item's icon, a driver or a 3D reference
        const target = { kind, id };
        if (fixedCode) target.code = fixedCode;
        const res = await post('/api/jobs', { kind: jk, target, spec: flatten(base, jk, specs), title: `${name}${target.code ? ' ' + target.code : ''} · ${method ? method.name : spec.method}` });
        if (!res.ok) { err.textContent = `${target.code || id}: ${res.error}`; return; }
        toast(`queued ${res.job ? '#' + shortId(res.job.id) : 'the job'}`, { label: 'Open Jobs', onClick: () => App.switchTab('jobs') });
        dlg.close(); await poll(); return;
      }
      // the looks: one job each, then each look's candidates; what went out is remembered (state.posted), so pressing
      // Queue again after a refusal sends only what is missing
      const n = fixedCode ? 1 : (spec.counts.looks || 1);
      let codes = fixedCode ? [fixedCode] : state.codes;
      if (codes.length < n) {
        const r = await fetchJson(`/api/content/${encodeURIComponent(kind)}/${encodeURIComponent(id)}/next_codes?n=${n}`, null);
        codes = r && r.ok && Array.isArray(r.codes) ? r.codes : nextCodes(record, n, existingCodes);
        state.codes = codes;
      }
      const made = [], errs = [];
      for (let i = 0; i < n; i++) {
        const code = codes[i];
        if (!state.posted.has(code)) {
          const ov = state.overrides[i] || {};
          const one = Object.assign({}, base, { recipe: Object.assign({}, base.recipe, ov) });
          if (ov.driver) one.recipe[spec.method === 'creature_ctl' ? 'drivers' : 'pose'] = ov.driver;   // an override from before pass 68
          delete one.recipe.driver;
          const res = await post('/api/jobs', { kind: 'look', target: { kind, id, code }, spec: flatten(one, 'look', specs), title: `${name} ${code} · ${method ? method.name : spec.method}` });
          if (!res.ok) { errs.push(`${code}: ${res.error}`); continue; }
          state.posted.add(code);
          made.push(res.job ? res.job.id : code);
        }
        for (const p of plan) {
          const cnt = Number(spec.counts[p.count]) || 0;
          const key = `${code}:${p.jk}`;
          if (cnt <= 0 || state.posted.has(key)) continue;
          const r2 = await post('/api/jobs', { kind: p.jk, target: { kind, id, code }, spec: candidateSpec(p, cnt, spec, specs), title: `${name} ${code} · ${p.label} ×${cnt}` });
          if (!r2.ok) { errs.push(`${code} ${p.label}: ${r2.error}`); continue; }
          state.posted.add(key);
          made.push(r2.job ? r2.job.id : key);
        }
      }
      const looksQueued = codes.slice(0, n).every((code) => state.posted.has(code));
      if (made.length) toast(`queued ${made.length} job${made.length > 1 ? 's' : ''}: ${made.map(shortId).join(', ')}`, { label: 'Open Jobs', onClick: () => App.switchTab('jobs') });
      if (errs.length) {
        err.textContent = errs.join(' · ');
        App.status(`${name}: ${errs.length} job${errs.length > 1 ? 's' : ''} refused: ${errs.join(' · ')}`, 'bad', errs.join('\n'));
      }
      if (looksQueued) {
        // every look is queued: the dialog closes; a refused candidate job stays visible in a long toast and the status line
        if (errs.length) toast(`${name}: the look${n > 1 ? 's are' : ' is'} queued, but ${errs.length} candidate job${errs.length > 1 ? 's were' : ' was'} refused: ${errs.join(' · ')}`, { label: 'Open Jobs', onClick: () => App.switchTab('jobs'), ms: 30000 });
        dlg.close();
      } else if (state.posted.size) queueBtn.textContent = 'Queue the rest';
      await poll();
      if (made.length && typeof Assets !== 'undefined' && typeof Assets.refreshRecord === 'function') { try { await Assets.refreshRecord(kind, id); } catch (_) { /* shown on the next render */ } }
      else if (made.length && kind !== 'hero' && typeof App.refreshCreatures === 'function') { try { await App.refreshCreatures(); } catch (_) { /* shown on the next render */ } }
    } finally { queueBtn.disabled = false; }
  }

  // start polling when the script loads (index.html loads jobs.js after app.js; App.init runs on DOMContentLoaded)
  if (typeof document !== 'undefined') {
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
  }

  return {
    render, poll, start, openForm, jobsFor, toast, openAsset, nextCodes, composeWords, methods, S, STATES, STATE_LABEL, REROLL, ROLES, FOLLOW, USES,
    // pass 68: the pure helpers (selftest_V checks them under Node) and the tables they read
    flatten, unflatten, queueOrder, queueLabel, heldLabel, withClearedFields, painterOfSpec, painterDiffers, candidatePlan, candidateRefusal, refUrl, candidateWords, sourceTag, lookRowKeys, rerollModes,
    GROUPS, LANE_ORDER, STILL_METHODS, MIN_CANDIDATES, CAND_KINDS, CAND_FIELDS, METHOD_ONLY, REROLL_FOR, CANDIDATES_HELP, FIRST_SEED_HELP, SEEDED_LOOKS,
  };
})();
if (typeof module !== 'undefined') module.exports = Jobs;
