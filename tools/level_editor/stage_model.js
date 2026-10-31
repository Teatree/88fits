// Pass 87 (lane STOOLS; Garry: "LevelEditor will have tabs in the Timeline for each Stage (more Stages can be added and it
// should be fairly simple to add (choosing the colouring should be possible too))"): the page-free edits behind the
// Timeline's stage tabs, run under Node by selftest_STOOLS87.py too. A map's stages are `timeline_data.stage_list` (one
// entry per stage, in order: {id, name, length, boss, description, difficulty, filter {color, strength}, hell, shot});
// stage k's window starts at the sum of the earlier lengths and its boss fires at its end (Model.stageList, the game's
// WaveTimeline.stage_window). Everything else on the timeline (roster rows, waves, events, the curves, specials' `from`)
// stays on the one run clock, so changing a stage's length, adding or deleting a stage moves the later stages' things
// with their windows. Every edit here changes `tl` in place and returns what it did in words (the confirm and the
// status line say it before and after).
'use strict';

const StageModel = (() => {
  const M = (typeof Model !== 'undefined') ? Model : (typeof require !== 'undefined' ? require('./model.js') : null);
  const isObj = (x) => x != null && typeof x === 'object' && !Array.isArray(x);
  const num = (v, d) => { const n = Number(v); return v == null || v === '' || !isFinite(n) ? d : n; };
  const r1 = (v) => Math.round(v * 10) / 10;
  const CUT = null;

  /** The filter a stage has when it names none: no tint (stage 1's look). */
  const FILTER_DEF = { color: '#000000', strength: 0 };
  /** Lane SLOOK's starting looks for a new stage after the first two (the evening and the blood moon). */
  const FILTER_PRESETS = [
    { id: 'none', label: 'None (daylight)', color: '#000000', strength: 0 },
    { id: 'evening', label: 'Evening (blue dim)', color: '#2a4a8c', strength: 0.35 },
    { id: 'bloodmoon', label: 'Blood moon (red)', color: '#8c1a1a', strength: 0.4 },
    { id: 'dawn', label: 'Dawn (warm pink)', color: '#d0707a', strength: 0.25 },
    { id: 'storm', label: 'Storm (green grey)', color: '#4a5a48', strength: 0.35 },
    { id: 'night', label: 'Night (deep blue)', color: '#101c40', strength: 0.55 },
  ];
  const HEX = /^#[0-9a-fA-F]{6}$/;

  /** A stage's filter as the game reads it: {color '#rrggbb', strength 0..1} (a bad colour = black, no strength). */
  function filterOf(e) {
    const f = isObj(e) && isObj(e.filter) ? e.filter : {};
    const color = typeof f.color === 'string' && HEX.test(f.color) ? f.color.toLowerCase() : FILTER_DEF.color;
    const strength = Math.min(1, Math.max(0, num(f.strength, FILTER_DEF.strength)));
    return { color, strength };
  }

  /** The boss event that ends stage s: a `boss` event at the window's end (±0.5 s), else null. {i, ev}. */
  function bossEventOf(tl, s) {
    const end = M.stageEnd(tl, s);
    let best = null;
    (Array.isArray(tl.events) ? tl.events : []).forEach((ev, i) => {
      if (!isObj(ev) || ev.type !== 'boss') return;
      const d = Math.abs(num(ev.t, 0) - end);
      if (d <= 0.5 && (!best || d < best.d)) best = { i, ev, d };
    });
    return best ? { i: best.i, ev: best.ev } : null;
  }

  /** The boss of stage s: the stage's own `boss`, else its boss event's creature (a single id), else ''. */
  function bossOf(tl, s) {
    const w = M.stageWindow(tl, s);
    if (w.boss) return w.boss;
    const be = bossEventOf(tl, s);
    if (be && typeof be.ev.enemy === 'string') return be.ev.enemy;
    return '';
  }

  /** Writes a stage_list from the fallback windows (stage_length x stages) when the map has none, so the stage tabs can
   *  edit it: ids s1.., names "Stage k", each window's boss from its boss event, no filter, `hell` from the third stage
   *  on (Game.gd's hell ground before pass 87: stage index 2 and later). Returns whether it wrote one. */
  function ensureList(tl) {
    if (M.hasStageList(tl)) return false;
    const L = M.stageList(tl);
    tl.stage_list = L.map((w) => ({ id: w.id, name: w.name, length: w.length, boss: bossOf(tl, w.i), description: '', difficulty: '',
      filter: Object.assign({}, FILTER_DEF), hell: w.i >= 2 }));
    return true;
  }

  /** A fresh id for a new stage (s<n> past every id in use). */
  function newStageId(tl) {
    const used = new Set((Array.isArray(tl.stage_list) ? tl.stage_list : []).filter(isObj).map((e) => String(e.id)));
    let n = used.size + 1;
    while (used.has('s' + n)) n++;
    return 's' + n;
  }

  // ------------------------------------------------------------------ moving times

  /** Every time on the run clock, mapped by f(t, what) -> a new time or CUT (null). `what` names the thing ({kind, i,
   *  edge}) so a rule can tell a stage's boss from the next stage's first row. Rows: start, end (`until`) and presence
   *  keyframes; waves: start and end; events; the cap, floor, HP and ATK curves' points; specials' `from`. A row or wave
   *  whose start is cut goes (named in `cut`); an end that is cut is set to `endFix` (the window edge the caller gives);
   *  a keyframe or curve point that is cut is dropped. Returns {moved, cut: [words], ends: [words]}. */
  function mapTimes(tl, f, endFix) {
    const out = { moved: 0, cut: [], ends: [] };
    const mv = (t, what) => { const v = f(num(t, 0), what); if (v !== CUT && v !== num(t, 0)) out.moved++; return v; };
    // roster rows
    if (Array.isArray(tl.roster)) {
      const keep = [];
      tl.roster.forEach((r, i) => {
        if (!isObj(r)) { keep.push(r); return; }
        const name = `row ${r.id || i + 1}`;
        const t0 = mv(r.t, { kind: 'row', i, edge: 'start' });
        let until = null;
        if (r.until != null && r.until !== '') {
          until = mv(r.until, { kind: 'row', i, edge: 'end', start: num(r.t, 0) });
          if (until === CUT) { until = endFix; out.ends.push(name); }
        }
        if (t0 === CUT || (until != null && t0 != null && until <= t0)) { out.cut.push(name); return; }
        r.t = t0;
        if (until != null) r.until = until;
        if (Array.isArray(r.weights)) {
          const ws = [];
          for (const p of r.weights) {
            if (!Array.isArray(p) || p.length < 2) { ws.push(p); continue; }
            const v = mv(p[0], { kind: 'key', i });
            if (v !== CUT) ws.push([v, p[1]]);
          }
          if (!ws.some((p) => Array.isArray(p)) && r.weights.length) {
            // every keyframe was cut: the row keeps its last weight from its start
            const last = r.weights.filter((p) => Array.isArray(p)).pop();
            ws.push([r.t, last ? last[1] : 1]);
          }
          r.weights = ws;
        }
        keep.push(r);
      });
      tl.roster = keep;
    }
    // the old waves[] blocks
    if (Array.isArray(tl.waves)) {
      const keep = [];
      tl.waves.forEach((w, i) => {
        if (!isObj(w)) { keep.push(w); return; }
        const name = `wave ${w.name || w.id || i + 1}`;
        const t0 = mv(w.t, { kind: 'wave', i, edge: 'start' });
        let until = null;
        if (w.until != null && w.until !== '') {
          until = mv(w.until, { kind: 'wave', i, edge: 'end', start: num(w.t, 0) });
          if (until === CUT) { until = endFix; out.ends.push(name); }
        }
        if (t0 === CUT || (until != null && until <= t0)) { out.cut.push(name); return; }
        w.t = t0;
        if (until != null) w.until = until;
        keep.push(w);
      });
      tl.waves = keep;
    }
    // events
    if (Array.isArray(tl.events)) {
      const keep = [];
      tl.events.forEach((ev, i) => {
        if (!isObj(ev)) { keep.push(ev); return; }
        const v = mv(ev.t, { kind: 'event', i, type: String(ev.type || '') });
        if (v === CUT) { out.cut.push(`${ev.type || 'event'} at ${M.clockText(num(ev.t, 0))}`); return; }
        ev.t = v;
        keep.push(ev);
      });
      tl.events = keep;
    }
    // the curves' points (a step at a boundary is two points at one second: curvePoints keeps its sides)
    const pts = (list, kind) => {
      if (!Array.isArray(list)) return list;
      const res = [];
      list.forEach((p, k) => {
        if (!Array.isArray(p) || p.length < 2) { res.push(p); return; }
        const same = list.filter((q) => Array.isArray(q) && num(q[0], 0) === num(p[0], 0));
        const v = mv(p[0], { kind, k, first: same[0] === p, last: same[same.length - 1] === p });
        if (v !== CUT) res.push([v].concat(p.slice(1)));
      });
      return res;
    };
    if (Array.isArray(tl.cap_curve)) tl.cap_curve = pts(tl.cap_curve, 'curve');
    if (Array.isArray(tl.floor_curve)) tl.floor_curve = pts(tl.floor_curve, 'curve');
    for (const key of ['hp_curve', 'damage_curve']) if (isObj(tl[key]) && Array.isArray(tl[key].points)) tl[key].points = pts(tl[key].points, 'curve');
    if (isObj(tl.specials) && tl.specials.from != null) {
      const v = mv(tl.specials.from, { kind: 'specials' });
      tl.specials.from = v === CUT ? endFix : v;
    }
    return out;
  }

  /** The per-stage lists (one entry per stage, the last holding for later stages): stage multipliers, the hell share,
   *  mutation offers, the weapon and line caps. */
  const PER_STAGE = ['stage_mults', 'hell_cap', 'path_times', 'weapon_cap', 'passive_cap'];

  // ------------------------------------------------------------------ the edits

  /** What setLength would do, without doing it (the confirm's words): {from, to, delta, moved, cut, ends, later}. */
  function lengthPreview(tl, s, len, mode) {
    const copy = JSON.parse(JSON.stringify(tl));
    return setLength(copy, s, len, mode);
  }

  /** Stage s (0-based) made `len` seconds long. The later stages' windows move by the difference and everything in them
   *  with them (rows, waves, events, curve points, specials' from). `mode` "keep": the stage's own things keep their
   *  times (growing: its rows that ran to its end run to the new end; shrinking: what lies past the new end is cut: rows
   *  and events starting there go, ends there come back to the new end, keyframes and curve points there drop); "stretch":
   *  its own times scale by new / old length from its start (nothing is cut; the pass 87 migration's rule). The boss at
   *  its end goes with the end. Returns {from, to, delta, moved, cut, ends, later (how many later stages moved)}. */
  function setLength(tl, s, len, mode) {
    ensureList(tl);
    const L = M.stageList(tl);
    const k = Math.max(0, Math.min(Math.floor(num(s, 0)), L.length - 1));
    const a = L[k].start, b = L[k].end, old = L[k].length;
    const nl = Math.max(1, Math.round(num(len, old)));
    const b2 = a + nl, delta = b2 - b;
    const stretch = mode === 'stretch';
    const f = (t, what) => {
      if (t < a) return t;
      if (t >= b) return r1(t + delta);
      // inside the stage (a <= t < b)
      if (stretch) return r1(a + (t - a) * nl / old);
      if (t <= b2) return t;
      // keep mode, shrinking: past the new end. A row's or wave's end comes back to the new end; the rest is cut
      return CUT;
    };
    const res = delta === 0 && !stretch ? { moved: 0, cut: [], ends: [] } : mapTimes(tl, f, b2);
    const entries = tl.stage_list.filter(isObj);
    entries[k].length = nl;
    return { from: old, to: nl, delta, moved: res.moved, cut: res.cut, ends: res.ends, later: L.length - 1 - k, mode: stretch ? 'stretch' : 'keep' };
  }

  /** A new stage at the end: the last stage's settings (its length, boss, filter, hell; a new id and name, no words),
   *  its boss event at its end (a copy of the last stage's, when it has one), the per-stage lists one longer (a copy of
   *  their last entry) where they had one entry a stage. No rows: the new window starts empty. Returns {i, id, start,
   *  end, boss}. */
  function addStage(tl) {
    const wrote = ensureList(tl);
    const L = M.stageList(tl);
    const last = L[L.length - 1];
    const le = last.entry || {};
    const id = newStageId(tl);
    const e = { id, name: `Stage ${L.length + 1}`, length: last.length, boss: bossOf(tl, last.i), description: '', difficulty: '',
      filter: Object.assign({}, filterOf(le)), hell: !!le.hell };
    if (le.shot) e.shot = '';
    tl.stage_list.push(e);
    const end = last.end + last.length;
    const be = bossEventOf(tl, last.i);
    if (!Array.isArray(tl.events)) tl.events = [];
    if (be) tl.events.push(Object.assign(JSON.parse(JSON.stringify(be.ev)), { t: end }));
    else if (e.boss) tl.events.push({ t: end, type: 'boss', enemy: e.boss });
    for (const key of PER_STAGE) {
      const arr = tl[key];
      if (Array.isArray(arr) && arr.length >= L.length && arr.length > 0) arr.splice(L.length, 0, JSON.parse(JSON.stringify(arr[L.length - 1])));
    }
    return { i: L.length, id, start: last.end, end, boss: e.boss, wrote };
  }

  /** What removeStage would do, without doing it: {cut, ends, moved, later}. */
  function removePreview(tl, s) {
    const copy = JSON.parse(JSON.stringify(tl));
    return removeStage(copy, s);
  }

  /** Stage s deleted: what lies wholly in its window goes (rows, waves and events in it, its boss at its end; curve points
   *  strictly inside it), what spans it is shortened, the later stages and their things move back by its length, and
   *  its entry in the per-stage lists goes (specials whose pool says "from stage N" past it count one less). The last
   *  remaining stage cannot go. Returns {ok, id, cut, ends, moved, later}. */
  function removeStage(tl, s) {
    ensureList(tl);
    const L = M.stageList(tl);
    if (L.length <= 1) return { ok: false, why: 'a map keeps at least one stage', cut: [], ends: [], moved: 0, later: 0 };
    const k = Math.max(0, Math.min(Math.floor(num(s, 0)), L.length - 1));
    const a = L[k].start, b = L[k].end, len = L[k].length;
    const f = (t, what) => {
      const kind = what && what.kind;
      if (t < a) return t;
      if (t > b) return r1(t - len);
      if (kind === 'event') {
        // the previous stage's boss sits at a (its own end): it stays; this stage's boss at b goes with it; anything
        // else at b is the next stage's first second
        if (t === a && what.type === 'boss' && k > 0) return t;
        if (t === b && what.type !== 'boss') return a;
        return CUT;
      }
      if (kind === 'curve') {
        // a step at a boundary is two points at one second: the left side of a and the right side of b survive (a step
        // from the previous stage's last value to the next stage's first, at a)
        if (t === a && what.first) return t;
        if (t === b && what.last) return a;
        return CUT;
      }
      if (kind === 'row' || kind === 'wave') {
        if (what.edge === 'start') return t === b ? a : (t === a ? a : CUT);
        // an end inside the window comes back to its start (a span that began before it ends there)
        return a;
      }
      // a keyframe at either edge marks a neighbour's presence there: it lands on a; inside the window it goes
      if (kind === 'key') return t === a || t === b ? a : CUT;
      if (kind === 'specials') return a;
      return CUT;
    };
    // a row or wave that starts inside the window but runs past it starts at a (it spans): give its start the window's
    // start before the map (so it is not cut)
    // (the last stage has no later window: what starts in it goes, open or not)
    const lastStage = k === L.length - 1;
    for (const list of [tl.roster, tl.waves]) {
      if (!Array.isArray(list)) continue;
      for (const r of list) {
        if (!isObj(r)) continue;
        const t0 = num(r.t, 0);
        const u = r.until == null || r.until === '' ? Infinity : num(r.until, Infinity);
        if (t0 > a && t0 < b && u > b && !lastStage) r.t = a;
      }
    }
    const res = mapTimes(tl, f, a);
    const entries = tl.stage_list.filter(isObj);
    const gone = entries[k];
    tl.stage_list = tl.stage_list.filter((e) => e !== gone);
    for (const key of PER_STAGE) {
      const arr = tl[key];
      if (Array.isArray(arr) && arr.length > k && arr.length > 1) arr.splice(k, 1);
    }
    if (isObj(tl.specials) && Array.isArray(tl.specials.pool)) {
      for (const p of tl.specials.pool) if (isObj(p) && num(p.stage, 1) > k + 1) p.stage = num(p.stage, 1) - 1;
    }
    return { ok: true, id: gone.id, cut: res.cut, ends: res.ends, moved: res.moved, later: L.length - 1 - k };
  }

  /** Stage s's boss set to `id`: the stage's `boss` and its boss event at the window's end (made when it has none). */
  function setBoss(tl, s, id) {
    ensureList(tl);
    const entries = tl.stage_list.filter(isObj);
    const k = Math.max(0, Math.min(Math.floor(num(s, 0)), entries.length - 1));
    entries[k].boss = String(id || '');
    const be = bossEventOf(tl, k);
    if (!Array.isArray(tl.events)) tl.events = [];
    if (be) {
      if (id) be.ev.enemy = String(id); else tl.events.splice(be.i, 1);
    } else if (id) {
      tl.events.push({ t: M.stageEnd(tl, k), type: 'boss', enemy: String(id) });
    }
    return { i: k, boss: entries[k].boss, event: !!(be || id) };
  }

  /** One key of stage s's entry set (name, description, difficulty, hell, shot, filter, xp_mult): the value as given; an
   *  empty word removes an optional key (xp_mult: empty or 1 removes it). */
  function setField(tl, s, key, value) {
    ensureList(tl);
    const entries = tl.stage_list.filter(isObj);
    const k = Math.max(0, Math.min(Math.floor(num(s, 0)), entries.length - 1));
    const e = entries[k];
    if (key === 'filter') e.filter = { color: HEX.test(String(value && value.color)) ? String(value.color).toLowerCase() : FILTER_DEF.color, strength: Math.round(Math.min(1, Math.max(0, num(value && value.strength, 0))) * 100) / 100 };
    else if (key === 'hell') e.hell = !!value;
    // pass 107 (lane XPT): the stage's XP multiplier on every kill (WaveTimeline.stage_xp_mult): a number >= 0, rounded to
    // 0.001; empty or 1 removes the key (1 is the game's default)
    else if (key === 'xp_mult') { const v = value === '' || value == null ? 1 : Math.max(0, num(value, 1)); if (Math.abs(v - 1) < 1e-9) delete e.xp_mult; else e.xp_mult = Math.round(v * 1000) / 1000; }
    else if (value === '' || value == null) { if (key === 'name') e.name = `Stage ${k + 1}`; else e[key] = ''; }
    else e[key] = String(value);
    return e;
  }

  /** The words a stage card shows: "Stage 2 · Dusk · 7:10–17:10 (10:00) · Gila Grande". */
  function describe(tl, s) {
    const w = M.stageWindow(tl, s);
    return `Stage ${w.i + 1} · ${w.name} · ${M.clockText(w.start)}–${M.clockText(w.end)} (${M.clockText(w.length)})`;
  }

  /** Checks on the stage list (the page's validation): {i (the stage), level, msg} each. */
  function issues(tl) {
    const out = [];
    if (!M.hasStageList(tl)) return out;
    const ids = new Set();
    tl.stage_list.forEach((e, i) => {
      if (!isObj(e)) { out.push({ i, level: 'error', msg: `stage_list entry ${i + 1} is not an object` }); return; }
      if (!(num(e.length, 0) >= 1)) out.push({ i, level: 'error', msg: `stage ${i + 1}: length must be at least 1 s` });
      const id = String(e.id == null ? '' : e.id);
      if (!id) out.push({ i, level: 'warn', msg: `stage ${i + 1} has no id (the game calls it s${i + 1})` });
      else if (ids.has(id)) out.push({ i, level: 'error', msg: `stage ${i + 1}: the id ${id} is used twice` });
      ids.add(id);
      const f = isObj(e.filter) ? e.filter : null;
      if (f && f.color != null && !HEX.test(String(f.color))) out.push({ i, level: 'warn', msg: `stage ${i + 1}: the filter colour ${f.color} is not #rrggbb` });
      if (f && f.strength != null && !(num(f.strength, -1) >= 0 && num(f.strength, 2) <= 1)) out.push({ i, level: 'warn', msg: `stage ${i + 1}: the filter strength must be 0 to 1` });
      if (e.xp_mult != null && !(typeof e.xp_mult === 'number' && isFinite(e.xp_mult) && e.xp_mult >= 0)) out.push({ i, level: 'warn', msg: `stage ${i + 1}: XP from kills (xp_mult) must be a number of 0 or more` });
      if (!bossOf(tl, i)) out.push({ i, level: 'warn', msg: `stage ${i + 1} has no boss at its end (${M.clockText(M.stageEnd(tl, i))}): a stage run ends at its boss` });
    });
    return out;
  }

  // ---------------------------------------------------------------- pass 116 (lane EDITOR): stage clocks, row numbers
  // Garry: "When viewing Timeline for a specific Stage let's display time from start of the run instead of total from
  // Stage 1 + 2, etc." and "Add an index indicator (count of the rows in the timeline) for each Stage". The file keeps
  // the one run clock; a stage tab shows and takes times from its window's start (0:00 = that stage's run start).

  /** A map-clock second as the stage tab shows it (off = the stage's start; null off = the whole map: unchanged). */
  function toStageClock(t, off) {
    if (t == null || t === '' || !isFinite(Number(t))) return t;
    return off == null ? Number(t) : Number(t) - Number(off);
  }
  /** A second typed on a stage tab back on the map clock. */
  function fromStageClock(v, off) {
    if (v == null || v === '' || !isFinite(Number(v))) return v;
    return off == null ? Number(v) : Number(v) + Number(off);
  }
  /** The stage a row belongs to: the window its start falls in (the last one past the end). */
  function stageOfT(windows, t) {
    const x = Number(t) || 0;
    for (let k = 0; k < windows.length; k++) if (x < windows[k].end) return k;
    return Math.max(0, windows.length - 1);
  }
  /** Every roster row's number within its stage: {byRow: [{stage, n}], counts: [rows a stage]}; inside a stage by start
   *  second, then the file's order. `windows` = [{start, end}] (Model.stageList). */
  function rowNumbers(rows, windows) {
    const W = windows && windows.length ? windows : [{ start: 0, end: Infinity }];
    const list = (rows || []).map((r, i) => ({ i, t: Number(r && r.t) || 0, stage: stageOfT(W, r && r.t) }));
    const counts = W.map(() => 0);
    const byRow = new Array(list.length);
    list.slice().sort((a, b) => a.stage - b.stage || a.t - b.t || a.i - b.i).forEach((x) => { counts[x.stage] += 1; byRow[x.i] = { stage: x.stage, n: counts[x.stage] }; });
    return { byRow, counts };
  }

  const api = { toStageClock, fromStageClock, stageOfT, rowNumbers, FILTER_DEF, FILTER_PRESETS, PER_STAGE, filterOf, bossEventOf, bossOf, ensureList, newStageId, mapTimes, lengthPreview,
    setLength, addStage, removePreview, removeStage, setBoss, setField, describe, issues };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  return api;
})();
