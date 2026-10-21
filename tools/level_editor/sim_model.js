// The Sim tab's page-free maths (pass 77, lane SIMUI): the chart definitions built from a sim's result.json (what each
// chart shows and how it was averaged, in Garry's words), the axes' ticks, the number formats, the breakdowns folded to
// seven entries and "Other", the readout at a second, the table view and the CSV, the settings' checks and the ETA (the
// same formula as tools/sim_batch.py eta_seconds). No DOM here: selftest_SIM77.py runs it under Node.
'use strict';

const SimModel = (() => {
  // the editor's dark series colours (style.css --s1..--s8: the dataviz reference palette's dark steps, validated as a
  // set against the surface #1a1a19); a breakdown takes them in this order, never cycled: the 8th entry on is "Other"
  const SLOTS = ['#3987e5', '#d95926', '#199e70', '#c98500', '#d55181', '#008300', '#9085e9', '#e66767'];
  const OTHER = '#6b6a65';          // the folded tail: a neutral, never a ninth hue
  const COMPARE = '#a8a79f';        // the compared sim: grey, long dashes, on every chart
  const COMPARE_DASH = '7 5';
  const SHORT_DASH = '3 3';         // a second measure of the same sim (the estimate, the max HP)
  const FOLD = 7;
  const BOARDS = [[0, 'none'], [1.5, 'a quarter'], [3, 'half'], [6, 'full']];
  // the death policies (round 2: "end" the default, "ad" when the runner has it, "keep"; "gold" only an older sim's)
  const DEATHS = { end: 'end the run at the first death', ad: 'revive once with an ad, then end', keep: 'keep playing, count every death',
    gold: 'revive with gold, then the run ends' };
  const DEFAULTS = { hero: 'drifter', players: 10, workers: 0, limit: 1500, board: 1.5, talents: null, board_label: '', death: 'end', seed: 1,
    map: 'red_canyon', fps: 60, note: '', fast: true };
  const TALENT_ORDER = ['grit', 'drive', 'stride', 'fortune', 'choice', 'nerve', 'study', 'spite'];
  const MAX_RANK = 6;

  // ------------------------------------------------------------------ formats

  function fmtT(s) {
    if (s == null || !isFinite(s)) return '–';
    const neg = s < 0; s = Math.abs(Math.round(s));
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
    return (neg ? '-' : '') + (h > 0 ? `${h}:${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}` : `${m}:${String(sec).padStart(2, '0')}`);
  }

  /** "25:00", "1500", "25m" -> seconds; null when it is not a time. */
  function parseT(str) {
    if (str == null) return null;
    const s = String(str).trim();
    let m = s.match(/^(\d+):(\d{1,2})(?::(\d{1,2}))?$/);
    if (m) return m[3] != null ? Number(m[1]) * 3600 + Number(m[2]) * 60 + Number(m[3]) : Number(m[1]) * 60 + Number(m[2]);
    m = s.match(/^(\d+(?:\.\d+)?)\s*m(?:in)?$/i);
    if (m) return Math.round(Number(m[1]) * 60);
    const n = Number(s);
    return s !== '' && isFinite(n) ? n : null;
  }

  /** A number for a label: 1,234 below 10 thousand, then 12.3K, 1.2M; small values keep a decimal. */
  function fmtNum(v, digits) {
    if (v == null || !isFinite(v)) return '–';
    const a = Math.abs(v);
    if (a >= 1e9) return (v / 1e9).toFixed(a >= 1e10 ? 0 : 1).replace(/\.0$/, '') + 'B';
    if (a >= 1e6) return (v / 1e6).toFixed(a >= 1e7 ? 0 : 1).replace(/\.0$/, '') + 'M';
    if (a >= 1e4) return (v / 1e3).toFixed(a >= 1e5 ? 0 : 1).replace(/\.0$/, '') + 'K';
    if (digits != null) return v.toFixed(digits);
    if (a >= 100) return Math.round(v).toLocaleString('en-US');
    if (a >= 10) return (Math.round(v * 10) / 10).toString();
    return (Math.round(v * 100) / 100).toString();
  }

  function fmtVal(v, fmt) {
    if (v == null || !isFinite(v)) return '–';
    if (fmt === 'pct') return `${Math.round(v)}%`;
    if (fmt === 'pct1') return `${(Math.round(v * 10) / 10).toFixed(1)}%`;
    if (fmt === 'sec') return v >= 90 ? fmtT(v) : `${Math.round(v * 10) / 10} s`;
    if (fmt === 'mult') return `×${(Math.round(v * 100) / 100).toString()}`;
    if (fmt === 'int') return fmtNum(Math.round(v));
    if (fmt === 'level') return (Math.round(v * 10) / 10).toString();
    return fmtNum(v);
  }

  function boardLabel(v) {
    const b = BOARDS.find((x) => Math.abs(x[0] - Number(v)) < 1e-6);
    return b ? b[1] : `${v} ranks`;
  }

  // ------------------------------------------------------------------ axes

  /** A tick step for the range [0, hi] in about n steps: 1, 2, 2.5 or 5 times a power of ten. */
  function niceStep(hi, n) {
    if (!(hi > 0)) return 1;
    const raw = hi / Math.max(1, n || 4);
    const p = Math.pow(10, Math.floor(Math.log10(raw)));
    for (const m of [1, 2, 2.5, 5, 10]) if (m * p >= raw) return m * p;
    return 10 * p;
  }

  /** The axis top: the next tick at or above hi (0..1 at least; 100 for a percentage chart). */
  function niceMax(hi, n) {
    if (!(hi > 0)) return 1;
    const st = niceStep(hi, n);
    return Math.ceil(hi / st - 1e-9) * st;
  }

  function yTicks(max, n) {
    const st = niceStep(max, n || 4);
    const out = [];
    for (let v = 0; v <= max + st * 1e-6; v += st) out.push(Math.round(v * 1e6) / 1e6);
    return out;
  }

  /** The x ticks (seconds) for a run of T seconds on px pixels: at least ~64 px apart, on whole minutes when it can. */
  function timeTicks(T, px) {
    const want = Math.max(2, Math.floor((px || 600) / 64));
    let step = 30;
    for (const s of [30, 60, 120, 180, 300, 600, 900, 1200, 1800, 3600, 7200]) { step = s; if (T / s <= want) break; }
    const out = [];
    for (let t = 0; t <= T + 1e-9; t += step) out.push(t);
    return out;
  }

  // ------------------------------------------------------------------ series

  /** A rolling mean over the last w seconds (the values before the first missing one start a new window). */
  function smooth(arr, w) {
    if (!Array.isArray(arr) || !(w > 1)) return arr;
    const out = new Array(arr.length).fill(null);
    let acc = 0, n = 0;
    const win = [];
    for (let i = 0; i < arr.length; i++) {
      const v = arr[i];
      if (v == null) { out[i] = null; acc = 0; n = 0; win.length = 0; continue; }
      win.push(v); acc += v; n++;
      if (win.length > w) { acc -= win.shift(); n--; }
      out[i] = acc / n;
    }
    return out;
  }

  function maxOf(arr) {
    let m = -Infinity;
    for (const v of arr || []) if (v != null && v > m) m = v;
    return m;
  }

  function firstSeen(arr) {
    for (let i = 0; i < (arr || []).length; i++) if (arr[i] != null && arr[i] > 0) return i;
    return Infinity;
  }

  /** A breakdown folded for a stacked chart: the `k` biggest (by `score`, else the last value / the sum) in the order
   *  they first appear, each with its fixed slot colour; the rest summed into "Other". `pin` (ids) keeps a colour map
   *  shared with another chart: an id already coloured keeps its colour. */
  function fold(bd, names, k, pin) {
    if (!bd || !bd.mean) return null;
    const ids = Object.keys(bd.mean);
    if (!ids.length) return null;
    const kk = Math.max(1, Math.min(k || FOLD, SLOTS.length - 1));
    const score = (id) => (bd.score && bd.score[id] != null ? bd.score[id] : bd.kind === 'cum' ? lastOf(bd.mean[id]) : sumOf(bd.mean[id]));
    const byScore = ids.slice().sort((a, b) => (score(b) - score(a)) || a.localeCompare(b));
    const cand = byScore.slice(0, ids.length <= kk + 1 ? ids.length : kk);
    // the order on the chart: first seen (the weapon taken first, the creature that came first), so a colour follows a
    // stable story rather than a rank; an id already coloured by another chart (`pin`) keeps its colour, a new one takes
    // the next free slot, and one that finds none goes into Other (never a ninth hue, never a grey item)
    cand.sort((a, b) => (firstSeen(bd.mean[a]) - firstSeen(bd.mean[b])) || (score(b) - score(a)) || a.localeCompare(b));
    const colors = pin || {};
    const used = new Set(Object.values(colors));
    const free = SLOTS.filter((c) => !used.has(c));
    const top = [];
    for (const id of cand) {
      if (!colors[id]) {
        if (!free.length) continue;
        colors[id] = free.shift();
      }
      top.push(id);
    }
    const rest = byScore.filter((id) => !top.includes(id));
    const items = top.map((id) => ({ id, label: (names && names[id]) || id, color: colors[id], values: bd.mean[id] }));
    let other = null;
    if (rest.length) {
      const n = bd.mean[rest[0]].length;
      const vals = new Array(n).fill(null);
      for (let i = 0; i < n; i++) {
        let s = null;
        for (const id of rest) { const v = bd.mean[id][i]; if (v != null) s = (s || 0) + v; }
        vals[i] = s;
      }
      // its parts kept, so the readout can name the biggest ones inside Other at any second
      other = { id: '__other', label: `Other (${rest.length})`, color: OTHER, values: vals, ids: rest,
        parts: rest.map((id) => ({ id, label: (names && names[id]) || id, values: bd.mean[id] })) };
    }
    return { items, other, colors, all: byScore };
  }

  function lastOf(arr) { for (let i = (arr || []).length - 1; i >= 0; i--) if (arr[i] != null) return arr[i]; return 0; }
  function sumOf(arr) { let s = 0; for (const v of arr || []) if (v != null) s += v; return s; }

  function totalOf(stack) {
    const parts = stack.items.concat(stack.other ? [stack.other] : []);
    const n = parts.length ? parts[0].values.length : 0;
    const out = new Array(n).fill(null);
    for (let i = 0; i < n; i++) {
      let s = null;
      for (const p of parts) { const v = p.values[i]; if (v != null) s = (s || 0) + v; }
      out[i] = s;
    }
    return out;
  }

  // ------------------------------------------------------------------ chests, power-ups, totems (pass 82, lane STATS)

  // Garry (pass 82): "a chart for Chests Picked up, Power-ups and Totems through a run". What each one counts, from a
  // run's events (analytics/SCHEMA.md). The same rule, line for line, in game/tools/sim_run.gd pickup_kind() (the sim's
  // series; the Watch's totals and marks) and tools/analytics_csv.py pickup_kind() (the rows CSV); selftest_STATS82 and
  // game/tests/pass82_stats_test.gd pin the three to one fixture. The colours: the palette's amber, blue and magenta,
  // checked as a set on the dark surface (the dataviz validator: every pair apart for colour-blind eyes, worst dE 13).
  const PICKUP_SERIES = [
    { key: 'chests', label: 'chests', color: SLOTS[3], words: 'chests opened (taken or skipped, boss chests too)' },
    { key: 'powerups', label: 'power-ups', color: SLOTS[0], words: 'power-ups picked up (every pickup but the small ones underfoot: cake slices, coin bags, pollen)' },
    { key: 'totems', label: 'totems', color: SLOTS[4], words: 'Totem Pole gifts taken' },
  ];
  const PICKUP_KEYS = PICKUP_SERIES.map((p) => p.key);

  /** A pickup's `small` as the game wrote it: true, or a number other than 0 (GDScript's bool()). */
  function isSmall(v) { return v === true || (typeof v === 'number' && v !== 0); }

  /** What an event counts towards: 'chests' (a `chest` event: one per chest opened, taken or skipped, a boss chest
   *  too), 'powerups' (a `pickup` whose `small` is not set: Heart, Magnet Pulse, Nuke, Berserk, Shield, Sprint,
   *  Timeout), 'totems' (a `totem` event: a Totem Pole's gift taken); '' for anything else. */
  function pickupKind(e) {
    if (e === null || typeof e !== 'object' || Array.isArray(e)) return '';
    const kind = String(e.kind != null ? e.kind : '');
    if (kind === 'chest') return 'chests';
    if (kind === 'pickup') return isSmall(e.small) ? '' : 'powerups';
    if (kind === 'totem') return 'totems';
    return '';
  }

  /** An event's play second (0 when it is not a number, as GDScript's float(e.get("t")) of a number reads it). */
  function evT(e) { return e && typeof e.t === 'number' && isFinite(e.t) ? e.t : 0; }

  /** {chests, powerups, totems}: each kind's event times, in order. */
  function pickupTimes(events) {
    const out = { chests: [], powerups: [], totems: [] };
    for (const e of Array.isArray(events) ? events : []) { const k = pickupKind(e); if (k) out[k].push(evT(e)); }
    for (const k of PICKUP_KEYS) out[k].sort((a, b) => a - b);
    return out;
  }

  /** {chests, powerups, totems}: how many so far at each of the rows' play seconds `ts` (an event counts from the
   *  first row whose t reaches it: e.t <= t + 0.001, as the deaths do). */
  function pickupCounts(events, ts) {
    const times = pickupTimes(events);
    const out = {};
    for (const k of PICKUP_KEYS) {
      const tk = times[k], arr = [];
      let i = 0;
      for (const t of ts || []) { const tt = Number(t) || 0; while (i < tk.length && tk[i] <= tt + 0.001) i++; arr.push(i); }
      out[k] = arr;
    }
    return out;
  }

  /** {chests, powerups, totems}: the run's totals (every event, the ones after its last row too). */
  function pickupTotals(events) {
    const times = pickupTimes(events);
    return { chests: times.chests.length, powerups: times.powerups.length, totems: times.totems.length };
  }

  // ------------------------------------------------------------------ the charts

  const ser = (res, key, field) => (res && res.series && res.series[key] ? res.series[key][field || 'mean'] : null);

  /** How many runs a result averages: the ones with data (a partial result has fewer than the settings ask for, a
   *  failed run has none); the settings' count only for a result without a summary. */
  function runsIn(res) {
    const s = (res && res.summary) || {};
    if (s.ok != null) return s.ok;
    if (res && Array.isArray(res.playing) && res.playing.length) return res.playing[0];
    return ((res && res.settings) || {}).players || 0;
  }

  /** The chart definitions for a result (and an optional compared result), in Garry's order and grouped in sections:
   *  [{id, section, title, how, fmt, lines, bands, stack, overlay, yMax, yMin}]. A line: {key, label, color, values,
   *  width, dash}; a band {label, lo, hi, color}; a stack {items, other} (bottom to top); overlay: the compared sim's
   *  lines. A chart whose data the runs do not carry is left out (missing() names it). `opts.raw` shows the DPS per
   *  second unsmoothed. Plain data in and out: the run dashboard reuses it (pass 78). A result of ONE run (the
   *  dashboard's open run, a one-player sim) draws no bands, says "this run" and leaves out the share of runs playing. */
  function charts(res, cmp, opts) {
    const o = opts || {};
    if (!res || !res.series) return [];
    const n = runsIn(res);   // the runs in this result (a partial one has fewer than were asked for)
    const one = n === 1;     // pass 78: one run (the run dashboard's open run): no bands, no "averaged over"
    const win = (res.rules || {}).dps_window || 5;
    const rwin = (res.rules || {}).rate_window || 10;
    const names = res.names || {};
    const cmpName = 'compared';
    const out = [];
    const has = (key) => !!(res.series[key] && (res.series[key].mean || res.series[key].median));
    const ov = (key, field, label) => (cmp && cmp.series && cmp.series[key] && cmp.series[key][field || 'mean'] ? [{ label: label || cmpName, values: cmp.series[key][field || 'mean'] }] : []);
    const playingNote = one ? 'for this run' : `averaged over the runs still playing at that second (${n} at the start)`;
    const band = (key, color, label, field) => (!one && res.series[key] && res.series[key].p10 ? [{ label: label || 'middle 80% of runs', lo: res.series[key].p10, hi: res.series[key].p90, color }] : []);
    const bandNote = one ? '' : ' The band holds the middle 80% of the runs.';
    const bandTail = one ? '' : '; the band is the middle 80%';
    const push = (section, c) => { c.section = section; out.push(c); };

    // ---- the hero
    const dpsKey = o.raw ? 'dps_raw' : 'dps';
    push('hero', { id: 'dps', title: 'Player DPS', fmt: 'num', unit: 'damage a second',
      how: o.raw ? `Damage dealt each second by every source (weapons, perks, blasts), per second as played, ${playingNote}. The dashed line is the build's own promise (the pause screen's estimate).`
        : one ? `Damage dealt each second by every source (weapons, perks, blasts), smoothed over ${win} s, ${playingNote}. The dashed line is the build's own promise (the pause screen's estimate).`
        : `Damage dealt each second by every source (weapons, perks, blasts), each run smoothed over ${win} s first, then ${playingNote}. The band holds the middle 80% of the runs (10th to 90th percentile). The dashed line is the build's own promise (the pause screen's estimate).`,
      lines: [{ key: dpsKey, label: o.raw ? 'real DPS (per second)' : `real DPS (${win} s)`, color: SLOTS[0], values: ser(res, dpsKey) || [] },
        { key: 'est', label: 'estimated DPS', color: SLOTS[6], values: ser(res, 'est') || [], dash: SHORT_DASH, width: 1.5 }],
      bands: o.raw ? [] : band('dps', SLOTS[0]), overlay: ov(dpsKey, 'mean', `${cmpName}: real DPS`) });
    push('hero', { id: 'hp', title: 'Player HP', fmt: 'num', unit: 'HP',
      how: `The hero's health at each second and his max health (dashed), ${playingNote}.${bandNote}`,
      lines: [{ key: 'hp', label: 'HP', color: SLOTS[2], values: ser(res, 'hp') || [] },
        { key: 'hp_max', label: 'max HP', color: SLOTS[2], values: ser(res, 'hp_max') || [], dash: SHORT_DASH, width: 1.25 }],
      bands: band('hp', SLOTS[2]), overlay: ov('hp', 'mean', `${cmpName}: HP`) });
    // pass 83 (lane SCALE): the hero's power level (HeroPower; a run recorded before pass 83 has none: no chart)
    if (has('power') && (ser(res, 'power') || []).some((v) => v > 0)) push('hero', { id: 'power', title: 'Hero power', fmt: 'num', unit: 'power (fresh Drifter = 1)',
      how: `The hero's power level at each second, ${playingNote}: √((full DPS ÷ 20.4) × (effective HP ÷ 100)). Full DPS = every weapon's damage a second on ONE target that every shot hits (the pause screen's estimate without its crowd guess, burns kept up, average crits); effective HP = (max HP + shield + 30 s of regen and lifesteal) ÷ ((1 − armour) × (1 − evade)). A fresh level-1 Drifter with the Revolver is 1; twice the DPS alone is 1.41, twice both is 2.${bandNote}`,
      lines: [{ key: 'power', label: 'power', color: SLOTS[4], values: ser(res, 'power') || [] }],
      bands: band('power', SLOTS[4]), overlay: ov('power', 'mean', `${cmpName}: power`) });

    // ---- death: the runs still playing, the deaths so far
    const pct = (arr, total) => (arr || []).map((v) => (v == null ? null : (100 * v) / Math.max(1, total)));
    const cmpN = cmp ? runsIn(cmp) || 1 : 1;
    if (!one) push('death', { id: 'playing', title: 'Runs still playing', fmt: 'pct', unit: '% of runs', yMax: 100,
      how: `The share of the ${n} runs still going at each second: a run stops at its end (a death it could not get up from, or the stop time). With "keep playing" every run goes to the stop.`,
      lines: [{ key: 'playing', label: 'still playing', color: SLOTS[0], values: pct(res.playing, n) }],
      overlay: cmp ? [{ label: `${cmpName}: still playing`, values: pct(cmp.playing, cmpN) }] : [] });
    push('death', { id: 'deaths', title: 'Deaths so far', fmt: 'num', unit: 'deaths a run',
      how: one ? 'How many times the hero has gone down by each second (revived or not), for this run: a fall the run ended at counts too.'
        : `How many times a run has gone down by each second (revived or not), averaged over all ${n} runs: a run that ended keeps its count to the right.`,
      lines: [{ key: 'deaths', label: one ? 'deaths' : 'deaths a run (mean)', color: SLOTS[7], values: ser(res, 'deaths') || [] }],
      overlay: ov('deaths', 'mean', `${cmpName}: deaths`) });

    // ---- difficulty: how hard is each second for the hero?
    const creatureColors = o.creatureColors || {};
    const bds = res.breakdowns || {};
    const killFold = fold(bds.kills_by, names, FOLD, creatureColors);
    const aliveFold = fold(bds.alive_by, names, FOLD, creatureColors);
    const hurtFold = fold(bds.took_by, names, FOLD, creatureColors);
    if (has('danger')) push('difficulty', { id: 'danger', title: 'Danger: health lost a second', fmt: 'pct1', unit: '% of max HP a second',
      how: `How much of his max health the hero loses each second before healing (the line), and after it (dashed: below 0 = healing more than he loses). 2% means a full bar lasts 50 s at that rate. ${one ? 'Over' : 'Each run over'} ${win} s, ${playingNote}${bandTail}.`,
      lines: [{ key: 'danger', label: 'lost (before healing)', color: SLOTS[7], values: ser(res, 'danger') || [] },
        { key: 'danger_net', label: 'net (after healing)', color: SLOTS[7], values: ser(res, 'danger_net') || [], dash: SHORT_DASH, width: 1.5 }],
      bands: band('danger', SLOTS[7]), overlay: ov('danger', 'mean', `${cmpName}: lost`) });
    if (has('keep_up')) push('difficulty', { id: 'keep_up', title: 'Keeping up with the crowd', fmt: 'sec', unit: 'seconds of his damage',
      how: 'How many seconds of his own damage the hero would need to kill every creature alive, the boss left out: rising = falling behind the crowd, flat or falling = keeping up. Dashed: the boss alone, seconds of his damage to kill it.' +
        (one ? ' For this run (blank where his damage is under 1 a second).' : ' The middle run at each second (a crowd over a DPS jumps where the DPS is small), the band the middle 80%.'),
      lines: [{ key: 'keep_up', label: 'to clear the crowd (no boss)', color: SLOTS[1], values: ser(res, 'keep_up', 'median') || [] },
        { key: 'boss_s', label: 'to kill the boss', color: SLOTS[4], values: ser(res, 'boss_s', 'median') || [], dash: SHORT_DASH, width: 1.5 }],
      bands: band('keep_up', SLOTS[1]), overlay: ov('keep_up', 'median', `${cmpName}: to clear the crowd`) });
    if (has('near3')) push('difficulty', { id: 'near', title: 'Close crowd', fmt: 'num', unit: 'creatures',
      how: `Creatures within 3 m of the hero: the ones that can reach him now${has('near6') ? ' (dashed: within 6 m)' : ''}, ${playingNote}${bandTail}.`,
      lines: [{ key: 'near3', label: 'within 3 m', color: SLOTS[1], values: ser(res, 'near3') || [] }]
        .concat(has('near6') ? [{ key: 'near6', label: 'within 6 m', color: SLOTS[1], values: ser(res, 'near6') || [], dash: SHORT_DASH, width: 1.5 }] : []),
      bands: band('near3', SLOTS[1]), overlay: ov('near3', 'mean', `${cmpName}: within 3 m`) });
    if (aliveFold) push('difficulty', { id: 'alive_by', title: 'Who is alive', fmt: 'num', unit: 'creatures',
      how: `How many of each creature are alive at that second (the biggest ${FOLD}, the rest as Other), ${playingNote}. The top edge is the whole crowd.`,
      stack: aliveFold, lines: [], overlay: ov('alive', 'mean', `${cmpName}: crowd`) });
    if (has('trouble')) push('difficulty', { id: 'trouble', title: one ? 'In trouble' : 'Runs in trouble', fmt: 'pct', unit: one ? '%' : '% of runs', yMax: 100,
      how: one ? 'Whether the hero is under 30% of his max health at that second: 100% while he is, 0% while he is not.' : `The share of the runs still playing whose hero is under 30% of his max health at that second.`,
      lines: [{ key: 'trouble', label: 'under 30% health', color: SLOTS[7], values: ser(res, 'trouble') || [] }], overlay: ov('trouble', 'mean', `${cmpName}: in trouble`) });
    if (hurtFold) push('difficulty', { id: 'hurt', title: 'What hurt the hero', fmt: 'num', unit: 'HP lost',
      how: `Health lost so far to each creature or attack (after shields and armour; the biggest ${FOLD}, the rest as Other), ${playingNote}. The top edge is all the health lost.`,
      stack: hurtFold, lines: [], overlay: [] });
    if (has('hits_ps')) push('difficulty', { id: 'hits', title: 'Hits taken', fmt: 'num', unit: 'hits a second',
      how: `Hits that reached the hero each second (shielded and evaded ones too), ${one ? '' : 'each run '}over ${rwin} s, ${playingNote}.`,
      lines: [{ key: 'hits_ps', label: 'hits a second', color: SLOTS[4], values: ser(res, 'hits_ps') || [] }], overlay: ov('hits_ps', 'mean', `${cmpName}: hits`) });
    const healFold = fold(bds.healed_by, names, FOLD);
    if (healFold) push('difficulty', { id: 'heal', title: 'Healing', fmt: 'num', unit: 'HP healed',
      how: `Health healed so far, by what gave it (regen, life steal, pickups, the level-up patch...), ${playingNote}.`,
      stack: healFold, lines: [], overlay: [] });
    // pass 84 (lane SIMVIEW): the regular channel's load (what the cap counts: each creature its cap share) beside the count
    const hasLoad = has('load');
    if (has('cap')) push('difficulty', { id: 'cap', title: 'The crowd against the cap', fmt: 'num', unit: 'creatures',
      how: `Creatures alive and the director's cap at that second (the timeline's cap curve as it played), ${playingNote}.` +
        (hasLoad ? ' The cap counts load, not heads: each creature its cap share (the fodder counts half), the hell channel apart (the dotted line is that load); the director spawns while the load is under the cap.' : ''),
      lines: [{ key: 'alive', label: 'alive', color: SLOTS[0], values: ser(res, 'alive') || [] },
        { key: 'cap', label: 'cap', color: SLOTS[3], values: ser(res, 'cap') || [], dash: SHORT_DASH, width: 1.5 }]
        .concat(hasLoad ? [{ key: 'load', label: 'load (counted against the cap)', color: SLOTS[0], values: ser(res, 'load') || [], dash: '1 3', width: 1.5 }] : []),
      overlay: ov('alive', 'mean', `${cmpName}: alive`) });
    if (has('cap_full')) push('difficulty', { id: 'cap_full', title: 'Cap full', fmt: 'pct', unit: '% of the second', yMax: 100,
      how: `How much of each second the director had no room for the regular rows (checked every 0.2 s: the load at or over the cap, or the bodies at the hard cap), ${playingNote}. 100% = full all second${one ? '' : ' in every run'}; while it is full no continuous row spawns, so a weak build starves the new rows.`,
      lines: [{ key: 'cap_full', label: 'cap full', color: SLOTS[7], values: (ser(res, 'cap_full') || []).map((v) => (v == null ? null : 100 * v)) }],
      overlay: cmp && cmp.series && cmp.series.cap_full ? [{ label: `${cmpName}: cap full`, values: cmp.series.cap_full.mean.map((v) => (v == null ? null : 100 * v)) }] : [] });
    if (has('challenge')) push('difficulty', { id: 'challenge', title: 'The crowd against the hero', fmt: 'num', unit: '× (threat ÷ his DPS × effective HP)',
      how: "The crowd's threat over the hero's strength at each second: threat = the sum over every creature alive (the boss left out) of its max HP × its bite a second (its bite's damage ÷ its bite cadence); his strength = his full DPS on one target × his effective HP (the Hero power chart's two parts). For one creature it is the seconds he needs to kill it × the share of his effective HP it bites off a second. Rising = the crowd outgrows him." +
        (one ? ' For this run.' : ' The middle run at each second (a ratio jumps where his numbers are small), the band the middle 80%.'),
      lines: [{ key: 'challenge', label: 'threat ÷ strength', color: SLOTS[1], values: ser(res, 'challenge', 'median') || [] }],
      bands: band('challenge', SLOTS[1]), overlay: ov('challenge', 'median', `${cmpName}: threat ÷ strength`) });
    if (has('kills_ps')) push('difficulty', { id: 'flow', title: 'Spawned and killed', fmt: 'num', unit: 'creatures a second',
      how: `Creatures killed${has('spawned_ps') ? ' and spawned' : ''} each second, ${one ? '' : 'each run '}over ${rwin} s, ${playingNote}.${has('spawned_ps') ? ' Kills above spawns = the hero is winning the room.' : ''}`,
      lines: [{ key: 'kills_ps', label: 'killed a second', color: SLOTS[2], values: ser(res, 'kills_ps') || [] }]
        .concat(has('spawned_ps') ? [{ key: 'spawned_ps', label: 'spawned a second', color: SLOTS[1], values: ser(res, 'spawned_ps') || [], dash: SHORT_DASH, width: 1.5 }] : []),
      overlay: ov('kills_ps', 'mean', `${cmpName}: killed`) });
    if (has('mult_hp')) push('difficulty', { id: 'strength', title: 'How strong a creature spawned now is', fmt: 'mult', unit: '× its base',
      how: `The HP and damage a creature spawned at that second gets on top of its own numbers (the stage, the timeline's curves, the hero's level; the map's own creature multipliers come on top), ${playingNote}.`,
      lines: [{ key: 'mult_hp', label: 'HP ×', color: SLOTS[1], values: ser(res, 'mult_hp') || [] },
        { key: 'mult_dmg', label: 'damage ×', color: SLOTS[4], values: ser(res, 'mult_dmg') || [], dash: SHORT_DASH, width: 1.5 }],
      overlay: ov('mult_hp', 'mean', `${cmpName}: HP ×`) });

    // ---- rewards
    const goldFold = fold(bds.gold_by, names, FOLD);
    push('rewards', { id: 'gold', title: 'Coins gained', fmt: 'int', unit: 'coins',
      how: `Every coin picked up so far (gems' gold, chests, bosses, Greed included; spending not taken off), ${playingNote}.` + (goldFold ? ' Split by where the coins came from.' : ''),
      stack: goldFold, lines: goldFold ? [] : [{ key: 'gold_total', label: 'coins gained', color: SLOTS[3], values: ser(res, 'gold_total') || [] }],
      overlay: ov('gold_total', 'mean', `${cmpName}: coins`) });
    const dmgFold = fold(bds.dmg_by, names, FOLD);
    push('rewards', { id: 'dmg', title: 'Damage dealt', fmt: 'num', unit: 'damage',
      how: `All the damage dealt so far, split by source (each weapon, its evolution, perks, the revive blast), ${playingNote}. The top edge is the total.`,
      stack: dmgFold, lines: dmgFold ? [] : [{ key: 'dmg_total', label: 'damage dealt', color: SLOTS[0], values: ser(res, 'dmg_total') || [] }],
      overlay: cmp ? [{ label: `${cmpName}: total`, values: (cmp.series.dmg_total ? cmp.series.dmg_total.mean : stackTotal(cmp, 'dmg_by')) }] : [] });
    if (killFold) push('rewards', { id: 'kills', title: 'Kills', fmt: 'int', unit: 'kills',
      how: `Creatures killed so far, split by creature (the biggest ${FOLD}, the rest as Other), ${playingNote}. The top edge is the total.`,
      stack: killFold, lines: [], overlay: ov('kills', 'mean', `${cmpName}: kills`) });
    else push('rewards', { id: 'kills', title: 'Kills', fmt: 'int', unit: 'kills', how: `Creatures killed so far, ${playingNote}.`,
      lines: [{ key: 'kills', label: 'kills', color: SLOTS[1], values: ser(res, 'kills') || [] }], overlay: ov('kills', 'mean', `${cmpName}: kills`) });
    // pass 95 (lane WORLD): the regular creatures that despawned far from the hero and out of view (a sim from pass 95 on)
    const despFold = fold(bds.despawned_by, names, FOLD, creatureColors);
    if (despFold) push('rewards', { id: 'despawned', title: 'Despawned out of view', fmt: 'int', unit: 'creatures',
      how: `Regular creatures that vanished so far because the hero left them more than the map's despawn distance behind, off the screen (no kill, no drop; their rows spawn again near him), split by creature (the biggest ${FOLD}, the rest as Other), ${playingNote}. The top edge is the total.`,
      stack: despFold, lines: [], overlay: [] });
    // pass 82 (lane STATS): chests, power-ups and totems picked up so far
    const pk = PICKUP_SERIES.filter((p) => has(p.key));
    if (pk.length) push('rewards', { id: 'pickups', title: 'Chests, power-ups, totems', fmt: 'level', unit: 'picked up',
      how: `${PICKUP_SERIES.map((p) => p.words).join(', ').replace(/, ([^,]*)$/, ' and $1').replace(/^./, (c) => c.toUpperCase())} so far, ${playingNote}.` +
        (one ? ' Each step is one picked up.' : ''),
      lines: pk.map((p) => ({ key: p.key, label: p.label, color: p.color, values: ser(res, p.key) || [] })),
      overlay: [].concat(...pk.map((p) => ov(p.key, 'mean', `${cmpName}: ${p.label}`))) });

    // ---- growth
    push('growth', { id: 'level', title: 'Hero level', fmt: 'level', unit: 'level',
      how: `The hero's level at each second, ${playingNote}.${bandNote}`,
      lines: [{ key: 'level', label: 'level', color: SLOTS[6], values: ser(res, 'level') || [] }],
      bands: band('level', SLOTS[6]), overlay: ov('level', 'mean', `${cmpName}: level`) });
    push('growth', { id: 'xp', title: 'Total XP gained', fmt: 'num', unit: 'XP',
      how: `Every point of XP gained so far (after the XP gain bonuses), ${playingNote}.`,
      lines: [{ key: 'xp_total', label: 'XP gained', color: SLOTS[6], values: ser(res, 'xp_total') || [] }],
      overlay: ov('xp_total', 'mean', `${cmpName}: XP`) });
    const held = bds.held_by && bds.held_by.mean ? bds.held_by.mean : null;
    if (held) {
      const kinds = ['weapons', 'evolutions', 'lines', 'passives', 'perks'].filter((k) => held[k]);
      push('growth', { id: 'build', title: 'The build: items held', fmt: 'level', unit: 'items',
        how: `How many weapons, evolutions, lines (the fortune cards), passive items and perks the hero holds at each second, ${playingNote}.`,
        lines: kinds.map((k, i) => ({ key: 'held_' + k, label: k, color: SLOTS[i], values: held[k] })), overlay: [] });
    }
    for (const c of out) { c.bands = c.bands || []; c.overlay = c.overlay || []; c.lines = c.lines.filter((l) => l.values && l.values.length); }
    return out;
  }

  // the sections the charts sit in, in Garry's order ("Player DPS, Player HP, Death, Difficulty, Coins, Total Damage
  // Dealt, Kills, hero level, total exp gained"), with one line each
  const SECTIONS = [
    { id: 'hero', title: 'The hero', words: 'How hard he hits and how healthy he stays.' },
    { id: 'death', title: 'Death', words: 'How many runs are still going, and how often the hero goes down.' },
    { id: 'difficulty', title: 'How hard is each second?', words: 'What the hero is up against: the health he loses, whether he keeps up with the crowd, what is close and what hurts.' },
    { id: 'rewards', title: 'Rewards', words: 'Coins, damage and kills so far.' },
    { id: 'growth', title: 'Growth', words: 'His level, his XP and his build.' },
  ];

  /** The difficulty charts these runs could not draw (their runner did not report the data): [chart title]. */
  function missing(res) {
    if (!res || !res.series) return [];
    const s = res.series, b = res.breakdowns || {};
    const out = [];
    if (!s.danger) out.push('Danger (needs the runs\' health lost a second: took)');
    if (!s.keep_up) out.push('Keeping up (needs the crowd\'s HP and the DPS)');
    if (!s.near3) out.push('Close crowd (needs near3)');
    if (!b.took_by) out.push('What hurt the hero (needs took_by)');
    if (!s.hits_ps) out.push('Hits taken (needs hits)');
    if (!b.healed_by) out.push('Healing (needs healed_by)');
    if (!s.spawned_ps) out.push('Spawned (needs spawned)');
    if (!s.mult_hp) out.push('How strong a creature spawned now is (needs mult_hp)');
    if (!b.held_by) out.push('The build (needs held_by)');
    if (!s.chests) out.push('Chests, power-ups, totems (needs chests, powerups, totems: a sim from pass 82 on)');
    return out;
  }

  function stackTotal(res, name) {
    const bd = (res.breakdowns || {})[name];
    if (!bd || !bd.mean) return [];
    const ids = Object.keys(bd.mean);
    if (!ids.length) return [];
    const n = bd.mean[ids[0]].length;
    const out = new Array(n).fill(null);
    for (let i = 0; i < n; i++) { let s = null; for (const id of ids) { const v = bd.mean[id][i]; if (v != null) s = (s || 0) + v; } out[i] = s; }
    return out;
  }

  /** The top of a chart's y axis: the highest value drawn (lines, band tops, the stack's total, the overlay). */
  function chartMax(c) {
    return chartRange(c).hi;
  }

  function minOf(arr) {
    let m = Infinity;
    for (const v of arr || []) if (v != null && v < m) m = v;
    return m;
  }

  /** The y axis: {lo, hi}: 0 up to the next round tick above the highest value drawn (lines, band tops, a stack's
   *  total, the compared sim); below 0 only when a value is (the net danger line), down to a round tick. */
  function chartRange(c) {
    let m = 0, lo = 0;
    for (const l of c.lines) { m = Math.max(m, maxOf(l.values)); lo = Math.min(lo, minOf(l.values)); }
    for (const b of c.bands) { m = Math.max(m, maxOf(b.hi)); lo = Math.min(lo, minOf(b.lo)); }
    if (c.stack) m = Math.max(m, maxOf(totalOf(c.stack)));
    for (const l of c.overlay) { m = Math.max(m, maxOf(l.values)); lo = Math.min(lo, minOf(l.values)); }
    const hi = c.yMax || niceMax(m > 0 ? m : 1, 4);
    if (!(lo < 0)) return { lo: 0, hi };
    const st = niceStep(hi - lo, 5);
    return { lo: -Math.ceil(-lo / st - 1e-9) * st, hi: Math.ceil(hi / st - 1e-9) * st || st };
  }

  /** The ticks between lo and hi (lo may be below 0: then 0 is always one of them). */
  function yTicksRange(lo, hi, n) {
    if (!(lo < 0)) return yTicks(hi, n);
    const st = niceStep(hi - lo, n || 5);
    const out = [];
    for (let v = Math.ceil(lo / st - 1e-9) * st; v <= hi + st * 1e-6; v += st) out.push(Math.round(v * 1e6) / 1e6);
    return out;
  }

  /** What the chart reads at second t: [{label, value, color, kind: line|band|stack|total|overlay, dash, sub}]. */
  function readout(c, t) {
    const at = (arr) => (arr && t >= 0 && t < arr.length ? arr[t] : null);
    const rows = [];
    for (const l of c.lines) {
      const band = c.bands.find((b) => b.color === l.color && l.dash == null);
      rows.push({ label: l.label, value: at(l.values), color: l.color, kind: 'line', dash: l.dash || null,
        sub: band && at(band.lo) != null ? `${fmtVal(at(band.lo), c.fmt)} – ${fmtVal(at(band.hi), c.fmt)}` : '' });
    }
    if (c.stack) {
      const parts = c.stack.items.concat(c.stack.other ? [c.stack.other] : []);
      const vals = parts.map((p) => ({ label: p.label, value: at(p.values), color: p.color, kind: 'stack',
        // inside Other: its three biggest at that second
        sub: p.parts ? p.parts.map((q) => [q.label, at(q.values) || 0]).filter((q) => q[1] > 0).sort((a, b) => b[1] - a[1]).slice(0, 3)
          .map((q) => `${fmtVal(q[1], c.fmt)} ${q[0]}`).join(', ') : '' }));
      vals.sort((a, b) => (b.value || 0) - (a.value || 0));
      rows.push({ label: 'total', value: at(totalOf(c.stack)), color: null, kind: 'total' });
      rows.push(...vals);
    }
    for (const l of c.overlay) rows.push({ label: l.label, value: at(l.values), color: COMPARE, kind: 'overlay', dash: COMPARE_DASH });
    return rows;
  }

  /** The table view: a row every `step` seconds and the last second: {head: [...], rows: [[t, ...values]]}. */
  function table(c, step, T) {
    const cols = [];
    for (const l of c.lines) cols.push({ label: l.label, values: l.values });
    for (const b of c.bands) { cols.push({ label: `${b.label}: low (10%)`, values: b.lo }); cols.push({ label: `${b.label}: high (90%)`, values: b.hi }); }
    if (c.stack) {
      for (const p of c.stack.items.concat(c.stack.other ? [c.stack.other] : [])) cols.push({ label: p.label, values: p.values });
      cols.push({ label: 'total', values: totalOf(c.stack) });
    }
    for (const l of c.overlay) cols.push({ label: l.label, values: l.values });
    const end = T != null ? T : Math.max(0, ...cols.map((x) => (x.values || []).length - 1));
    const ts = [];
    for (let t = 0; t <= end; t += step || 60) ts.push(t);
    if (ts[ts.length - 1] !== end) ts.push(end);
    return { head: ['time'].concat(cols.map((x) => x.label)), rows: ts.map((t) => [t].concat(cols.map((x) => (x.values && t < x.values.length ? x.values[t] : null)))) };
  }

  function csv(c, T) {
    const tb = table(c, 1, T);
    const q = (s) => (/[",\n]/.test(String(s)) ? `"${String(s).replace(/"/g, '""')}"` : String(s));
    const lines = [tb.head.map(q).join(',')];
    for (const r of tb.rows) lines.push([r[0]].concat(r.slice(1).map((v) => (v == null ? '' : String(v)))).join(','));
    return lines.join('\n') + '\n';
  }

  // ------------------------------------------------------------------ the header, the tiles

  function settingsLine(s, heroName) {
    const st = s || {};
    // pass 87 (lane STOOLS): the stage the runs played
    return `${heroName || st.hero} · ${st.stage ? 'stage ' + st.stage + ' · ' : ''}${st.players} run${st.players === 1 ? '' : 's'} to ${fmtT(st.limit)} · Upgrade board ${boardWords(st)} · ${DEATHS[st.death] || st.death} · seed ${st.seed}` +
      (st.fast === false ? ' · everything drawn (sim mode off)' : '');
  }

  /** A board's ranks: {talent: picks} -> how many ranks bought. */
  function boardRanks(t) {
    let n = 0;
    for (const k of Object.keys(t || {})) n += String(t[k] || '').length;
    return n;
  }

  /** The board in words: its name and its ranks, "a quarter (12 of 48 ranks)", "my save (16 of 48 ranks)". */
  function boardWords(st) {
    const s = st || {};
    const name = s.board_label || (s.board != null && Number(s.board) >= 0 ? boardLabel(s.board) : 'custom');
    return s.talents ? `${name} (${boardRanks(s.talents)} of ${MAX_RANK * TALENT_ORDER.length} ranks)` : name;
  }

  /** A talent's picks with rank r: kept up to r, a new rank in `form` (0/1; else the last one's, else A). */
  function setRank(picks, r, form) {
    const p = String(picks || '');
    const rr = Math.max(0, Math.min(MAX_RANK, Math.round(Number(r) || 0)));
    if (rr <= p.length) return p.slice(0, rr);
    const f = form === 1 || form === 'B' ? 'B' : form === 0 || form === 'A' ? 'A' : (p.slice(-1) || 'A');
    return p + f.repeat(rr - p.length);
  }

  /** The preset a board equals ({key, label} of meta.presets), else null (custom). */
  function presetOf(t, presets) {
    const key = (x) => TALENT_ORDER.map((k) => `${k}:${(x || {})[k] || ''}`).join(',');
    const want = key(t);
    return (presets || []).find((p) => key(p.talents) === want) || null;
  }

  /** "2 Padding, 1 Plate" for mixed picks; the form's name for uniform ones; '' for none. */
  function picksWords(picks, forms) {
    const p = String(picks || '');
    if (!p) return '';
    const a = (p.match(/A/g) || []).length, b = p.length - a;
    const nm = (i) => ((forms || [])[i] || {}).name || 'AB'[i];
    if (!a || !b) return nm(a ? 0 : 1);
    return `${a} ${nm(0)}, ${b} ${nm(1)}`;
  }

  /** The stat tiles over the charts: [{label, value, note}] from the summary (each run's own end, never survivors only). */
  function tiles(res) {
    const s = (res && res.summary) || {};
    const st = (res && res.settings) || {};
    const names = (res && res.names) || {};
    const out = [];
    out.push({ label: `Runs that reached ${fmtT(st.limit)}`, value: `${s.reached_limit != null ? s.reached_limit : '–'} of ${s.ok != null ? s.ok : '–'}`,
      note: s.failed ? `${s.failed} run${s.failed > 1 ? 's' : ''} failed to play` : 'played to the stop time' });
    out.push({ label: 'A run ended at (median)', value: fmtT(s.median_end_t), note: 'half the runs went further' });
    out.push({ label: 'Deaths a run', value: fmtNum(s.deaths_mean), note: s.revives_mean ? `${fmtNum(s.revives_mean)} revived a run` : 'mean over every run' });
    out.push({ label: 'Level at the end', value: fmtNum(s.level_mean), note: 'mean of each run\'s last level' });
    out.push({ label: 'Kills a run', value: fmtNum(s.kills_mean), note: 'by each run\'s end' });
    out.push({ label: 'Coins a run', value: fmtNum(s.gold_mean), note: 'gained by each run\'s end' });
    // pass 82: chests, power-ups, totems a run (a result from before pass 82 has none)
    if (s.chests_mean != null || s.powerups_mean != null || s.totems_mean != null) {
      out.push({ label: 'Chests · power-ups · totems a run', value: [s.chests_mean, s.powerups_mean, s.totems_mean].map((v) => fmtNum(v)).join(' · '),
        note: 'picked up by each run\'s end' });
    }
    for (const b of s.bosses || []) {
      const nm = names[b.id] || b.id;
      out.push({ label: `${nm}${b.occurrence > 1 ? ' #' + b.occurrence : ''}`, value: `${b.beaten} of ${b.reached}`,
        note: `beaten of the runs that met it${b.fight_s != null ? ` · fight ~${fmtT(b.fight_s)}` : ''}${b.mult != null ? ` · HP ×${fmtNum(b.mult)} (pegged to DPS)` : ''}` });
    }
    return out;
  }

  // ------------------------------------------------------------------ the settings, the ETA

  function cleanSettings(raw, limits) {
    const L = limits || {};
    const r = Object.assign({}, DEFAULTS, raw || {});
    const probs = [];
    const num = (key, lo, hi, int) => {
      let v = Number(r[key]);
      if (!isFinite(v)) { probs.push(`${key} must be a number`); v = DEFAULTS[key]; }
      if (int) v = Math.round(v);
      if (v < lo || v > hi) { probs.push(`${key} must be between ${lo} and ${hi}`); v = Math.min(hi, Math.max(lo, v)); }
      r[key] = v;
    };
    num('players', 1, L.max_players || 100, true);
    num('workers', 0, L.max_workers || 14, true);   // 0 = auto
    num('limit', L.limit_min || 30, L.limit_max || 10800, true);
    num('seed', 0, 2147483647, true);
    num('fps', 10, 240, true);
    num('board', 0, 6, false);
    const deaths = L.deaths || ['end', 'ad', 'keep'];
    if (!deaths.includes(r.death)) { probs.push(`on death must be one of ${deaths.join(', ')}`); r.death = 'end'; }
    if (r.workers <= 0) r.workers = Math.max(1, Math.min(r.players, (L.max_workers && L.max_workers < 1000 ? L.max_workers : Math.max(1, (L.cores || 8) - 2))));
    if (r.workers > r.players) r.workers = r.players;
    r.note = String(r.note || '').trim().slice(0, 200);
    r.fast = !(r.fast === false || ['0', 'false', 'no', 'off'].includes(String(r.fast).trim().toLowerCase()));
    return { settings: r, problems: probs };
  }

  /** sim_batch.speed_at: a run keeps about two logical processors busy, so past half of them runs share. */
  function speedAt(ppw, kMeas, k, cores) {
    const half = Math.max(1, (cores || 8) / 2);
    const load = (x) => Math.max(1, x / half);
    return (ppw * load(kMeas)) / load(k);
  }

  /** sim_batch.eta_seconds, the same numbers (selftest_SIM77 pins the two together). */
  function etaSeconds(raw, speed, cores, syncS) {
    const s = cleanSettings(raw, { max_workers: 1000, cores, deaths: Object.keys(DEATHS) }).settings;
    const sp = speed || {};
    const k = Math.max(1, Math.min(s.workers, s.players));
    const ppw = speedAt(Number(sp.slow) || Number(sp.play_per_wall) || 2.5, Math.max(1, Math.round(Number(sp.workers) || 6)), k, cores);   // a round ends with its slowest run
    const per = (Number(sp.boot_s) || 18) + s.limit / Math.max(0.05, ppw);
    const rounds = Math.ceil(s.players / k);
    return Math.round((syncS == null ? 20 : syncS) + rounds * per + 3);
  }

  /** A y-axis label: one unit for the whole axis (0, 5K, 10K, 15K rather than 0, 5,000, 10K), % on a share. */
  function tickLabel(v, max, fmt) {
    if (fmt === 'pct') return `${Math.round(v)}%`;
    if (fmt === 'pct1') return `${Math.round(v * 10) / 10}%`;
    if (fmt === 'mult') return `×${Math.round(v * 100) / 100}`;
    if (fmt === 'sec') return max >= 120 ? fmtT(v) : `${Math.round(v * 10) / 10} s`;   // one unit for the whole axis
    if (v === 0) return '0';
    const trim = (x) => String(Math.round(x * 100) / 100);
    if (max >= 1e9) return trim(v / 1e9) + 'B';
    if (max >= 1e6) return trim(v / 1e6) + 'M';
    if (max >= 1e4) return trim(v / 1e3) + 'K';
    return Math.abs(v) >= 1000 ? Math.round(v).toLocaleString('en-US') : trim(v);
  }

  /** A boss's name for a marker: without a leading "The", its first word ("Tumbleweed", "Gila", "Brander"). */
  function shortName(name) {
    const s = String(name || '').replace(/^the\s+/i, '').trim();
    return s.split(/\s+/)[0] || s;
  }

  function fmtDuration(s) {
    if (s == null || !isFinite(s)) return '?';
    if (s < 90) return `${Math.round(s)} s`;
    if (s < 5400) return `${Math.round(s / 60)} min`;
    return `${Math.floor(s / 3600)} h ${Math.round((s % 3600) / 60)} min`;
  }

  return {
    SLOTS, OTHER, COMPARE, COMPARE_DASH, SHORT_DASH, FOLD, BOARDS, DEATHS, DEFAULTS, tickLabel, shortName,
    SECTIONS, missing, chartRange, yTicksRange, TALENT_ORDER, MAX_RANK, boardRanks, boardWords, setRank, presetOf, picksWords,
    runsIn, fmtT, parseT, fmtNum, fmtVal, boardLabel, niceStep, niceMax, yTicks, timeTicks, smooth, fold, totalOf, charts, chartMax,
    readout, table, csv, settingsLine, tiles, cleanSettings, speedAt, etaSeconds, fmtDuration, maxOf, firstSeen,
    PICKUP_SERIES, PICKUP_KEYS, isSmall, pickupKind, pickupTimes, pickupCounts, pickupTotals,
  };
})();

if (typeof module !== 'undefined' && module.exports) module.exports = SimModel;
