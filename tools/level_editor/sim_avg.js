// The Sim's averaging, in the page (pass 78, lane DASH; Garry: "Add those charts to our Local Run Analytics dashboard so
// their formats match" and "I want to see it for one player in particular or as an average for several players").
// Page-free, run under Node by selftest_DASH78.py:
//  - aggregate(players, settings, meta, names): tools/sim_batch.py aggregate() line by line (player_grid, the 5 s DPS
//    smoothing, the difficulty series, the means over the runs still playing, the p10/p90 bands, the medians of the
//    ratios, deaths over every run, the breakdown means, the stage and boss markers, the summary, the runs one by one),
//    with Python's own rounding (round half to even on the exact binary value) so the two give the same numbers; the
//    selftest runs both on the same player files and compares them.
//  - fromRecord(record): a run record (core/systems/RunAnalytics.gd, analytics/runs/<stamp>.json, schema 1 or 2; a
//    remote run is the same file) as one player in the Sim's per-player schema (tools/dl/p77/keys_SIMRUN.md), the
//    mapping of game/tools/sim_run.gd series() and events_out() line by line (Godot's snappedf included); a fixture
//    the gdUnit test pass78_dash_test writes from the GDScript pins the two together.
// So the Sim tab's sims, the runs played on the PC and the runs downloaded from PostHog all average the same way and
// draw with the same chart definitions (sim_model.js).
'use strict';

const SimAvg = (() => {
  // pass 82 (lane STATS): the chests / power-ups / totems rule lives in sim_model.js (one copy for every page)
  const SM = typeof SimModel !== 'undefined' ? SimModel : (typeof require === 'function' ? require('./sim_model.js') : null);
  // ------------------------------------------------------------------ sim_batch.py's constants
  const SCHEMA = 1;
  const DPS_WINDOW = 5;
  const RATE_WINDOW = 10;
  const TROUBLE_FRAC = 0.30;
  const FOLD_DEFAULT = 7;
  const LEVEL_SERIES = ['hp', 'hp_max', 'est', 'alive', 'cap', 'press_hp', 'press_dmg', 'boss_hp', 'boss_hp_abs', 'level', 'clock', 'stage',
    'phase', 'gold', 'near3', 'near6', 'mult_hp', 'mult_dmg'];
  // pass 82: chests, powerups, totems (sim_run.gd's counts so far, like deaths but averaged over the runs still playing)
  const CUM_SERIES = ['gold_total', 'kills', 'xp_total', 'deaths', 'dmg_total', 'chests', 'powerups', 'totems'];
  const RATE_SERIES = ['dps', 'took', 'healed', 'hits', 'spawned'];
  const BAND_SERIES = ['hp', 'dps', 'level', 'press_hp', 'press_dmg', 'danger', 'near3', 'near6'];
  const MEDIAN_SERIES = ['keep_up', 'boss_s'];
  const BREAKDOWNS = { dmg_by: 'cum', kills_by: 'cum', gold_by: 'cum', took_by: 'cum', healed_by: 'cum', alive_by: 'level', held_by: 'level' };
  const SOURCE_WORDS = { blast: 'Blast', revive: 'Revive blast', grand_finale: 'Grand Finale', powder_keg: 'Powder Keg',
    loose_rocket: 'Loose rocket', thorns: 'Thorns', other: 'Other' };

  const own = (o, k) => o != null && Object.prototype.hasOwnProperty.call(o, k);
  const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

  // ------------------------------------------------------------------ Python's numbers

  /** How many binary digits a finite double has after the point (0 for a whole number). */
  function fracBits(x) {
    let y = Math.abs(x), k = 0;
    while (y !== Math.floor(y) && k < 1100) { y *= 2; k++; }
    return k;
  }

  /** Python's round(x, nd): the decimal nearest to x's exact binary value, an exact tie to the even neighbour (toFixed
   *  is exact too but breaks a tie away from zero). A tie is exact only when x has exactly nd + 1 binary digits after
   *  the point (x = odd / 2^(nd+1)). */
  function pyRound(x, nd) {
    if (typeof x !== 'number' || !isFinite(x)) return x;
    nd = nd || 0;
    if (Math.abs(x) >= 1e21) return x;
    let s = x.toFixed(nd);
    if (fracBits(x) === nd + 1) {
      const neg = s[0] === '-';
      const digits = s.replace('-', '').replace('.', '');
      if ((digits.charCodeAt(digits.length - 1) - 48) % 2 === 1) {
        const t = (BigInt(digits) - 1n).toString().padStart(nd + 1, '0');
        s = (neg ? '-' : '') + (nd > 0 ? t.slice(0, t.length - nd) + '.' + t.slice(t.length - nd) : t);
      }
    }
    const v = Number(s);
    return v === 0 ? 0 : v;   // no -0
  }

  /** sim_batch._num: a finite number, else `def`. Python's float() reads numbers, booleans and numeric text. */
  function num(v, def) {
    const d = def === undefined ? 0 : def;
    if (typeof v === 'number') return isFinite(v) ? v : d;
    if (typeof v === 'boolean') return v ? 1 : 0;
    if (typeof v === 'string' && v.trim() !== '' && /^[\s+-]*[\d.]/.test(v)) { const f = Number(v.trim()); return isFinite(f) ? f : d; }
    return d;
  }

  /** sim_batch._clock_s: seconds, or "m:ss". */
  function clockS(v) {
    if (typeof v === 'string' && v.includes(':')) {
      const bits = v.split(':');
      const a = Number(bits[0]), b = Number(bits[1]);
      return isFinite(a) && isFinite(b) && bits[0].trim() !== '' && bits[1].trim() !== '' ? a * 60 + b : 0;
    }
    return num(v);
  }

  /** sim_batch._r: 0.1 from 100 up, 0.01 from 1, else 0.001; whole numbers as whole; ints and the rest as they are. */
  function r(x) {
    if (x == null) return null;
    if (typeof x !== 'number') return x;
    if (!isFinite(x)) return null;
    const ax = Math.abs(x);
    return pyRound(x, ax >= 100 ? 1 : ax >= 1 ? 2 : 3);
  }

  /** sim_batch.pct: the q-th quantile of a sorted list, linear between the nearest ranks. */
  function pct(vals, q) {
    if (!vals || !vals.length) return null;
    if (vals.length === 1) return vals[0];
    const pos = q * (vals.length - 1);
    const lo = Math.floor(pos);
    const hi = Math.min(vals.length - 1, lo + 1);
    return vals[lo] + (vals[hi] - vals[lo]) * (pos - lo);
  }

  /** statistics.median over the values that are not null (null when none). */
  function median(vals) {
    const v = (vals || []).filter((x) => x != null).sort((a, b) => a - b);
    if (!v.length) return null;
    const n = v.length;
    return n % 2 === 1 ? v[(n - 1) / 2] : (v[n / 2 - 1] + v[n / 2]) / 2;
  }

  const sortNum = (a) => a.slice().sort((x, y) => x - y);
  const cmpStr = (a, b) => (a < b ? -1 : a > b ? 1 : 0);

  // ------------------------------------------------------------------ one player on whole seconds (player_grid)

  function rolling(arr, end, w) {
    const out = new Array(arr.length).fill(null);
    let acc = 0;
    const win = [];
    for (let s = 0; s <= end; s++) {
      const v = arr[s] || 0;
      win.push(v);
      acc += v;
      if (win.length > w) acc -= win.shift();
      out[s] = acc / win.length;
    }
    return out;
  }

  function bossAbs(d, series, end, T) {
    if (own(series, 'boss_hp_abs')) return series.boss_hp_abs.map((v) => (v != null ? v : null));
    const bh = series.boss_hp;
    if (!bh) return null;
    let mxv = -Infinity;
    for (const v of bh) mxv = Math.max(mxv, v || 0);
    if (mxv > 1.5) return bh;
    const mx = new Array(T + 1).fill(0);
    let cur = 0;
    const evs = (Array.isArray(d.events) ? d.events : []).filter((e) => isObj(e) && (e.kind === 'boss_start' || e.kind === 'boss_end'));
    evs.sort((a, b) => num(a.t) - num(b.t));
    let i = 0;
    for (let s = 0; s <= end; s++) {
      while (i < evs.length && num(evs[i].t) <= s + 0.5) {
        cur = evs[i].kind === 'boss_start' ? num(evs[i].hp) : 0;
        i++;
      }
      mx[s] = cur;
    }
    const out = [];
    for (let s = 0; s <= T; s++) out.push(s <= end && bh[s] != null ? (bh[s] || 0) * mx[s] : null);
    return out;
  }

  function deriveDifficulty(d, series, end, T) {
    const hp = series.hp, hm = series.hp_max, took = series.took, healed = series.healed;
    const range = (f) => { const out = []; for (let s = 0; s <= T; s++) out.push(f(s)); return out; };
    if (took && hm) {
      const lost = range((s) => (s <= end && hm[s] ? (100.0 * (took[s] || 0)) / hm[s] : null));
      series.danger = rolling(lost.map((v) => v || 0), end, DPS_WINDOW);
      if (healed) {
        const net = range((s) => (s <= end && hm[s] ? (100.0 * ((took[s] || 0) - (healed[s] || 0))) / hm[s] : 0));
        series.danger_net = rolling(net, end, DPS_WINDOW);
      }
    }
    if (hp && hm) series.trouble = range((s) => (s <= end && hm[s] ? ((hp[s] || 0) < TROUBLE_FRAC * hm[s] ? 100.0 : 0.0) : null));
    if (series.kills) {
      const k = series.kills;
      const per = [];
      for (let s = 0; s <= end; s++) per.push(s > 0 ? Math.max(0, (k[s] || 0) - (k[s - 1] || 0)) : (k[0] || 0));
      for (let s = end + 1; s <= T; s++) per.push(null);
      series.kills_ps = rolling(per, end, RATE_WINDOW);
    }
    for (const [key, out] of [['spawned', 'spawned_ps'], ['hits', 'hits_ps']]) if (series[key]) series[out] = rolling(series[key], end, RATE_WINDOW);
    const dps = series.dps, crowd = series.press_hp;
    if (dps && crowd) {
      const boss = bossAbs(d, series, end, T) || new Array(T + 1).fill(0);
      const ku = new Array(T + 1).fill(null), bs = new Array(T + 1).fill(null);
      for (let s = 0; s <= end; s++) {
        const dv = dps[s] || 0;
        if (dv < 1.0) continue;
        const b = boss[s] || 0;
        ku[s] = Math.max(0, (crowd[s] || 0) - b) / dv;
        if (b > 0) bs[s] = b / dv;
      }
      series.keep_up = ku;
      series.boss_s = bs;
    }
  }

  /** sim_batch.player_grid: [series, end, breakdowns] for one player on the seconds 0..T. */
  function playerGrid(d, T) {
    const t = (Array.isArray(d.t) ? d.t : []).map((x) => pyRound(num(x), 0));
    const n = t.length;
    let tmax = -Infinity;
    for (const x of t) if (x > tmax) tmax = x;
    const end = Math.max(0, Math.min(T, n ? tmax : 0));
    const idx = new Array(end + 1).fill(null);
    t.forEach((s, i) => { if (s >= 0 && s <= end) idx[s] = i; });
    let first = null;
    for (const i of idx) if (i !== null) { first = i; break; }
    const grid = (arr, kind, conv) => {
      const cv = conv || num;
      const out = new Array(T + 1).fill(null);
      if (!Array.isArray(arr) || arr.length !== n || first === null) return out;
      let last = null;
      for (let s = 0; s <= end; s++) {
        const i = idx[s];
        if (i !== null) { last = cv(arr[i]); out[s] = last; }
        else if (last !== null) out[s] = kind !== 'rate' ? last : 0;
        else out[s] = kind === 'level' ? cv(arr[first]) : 0;
      }
      return out;
    };
    const series = {};
    for (const key of LEVEL_SERIES) if (own(d, key)) series[key] = grid(d[key], 'level', key === 'clock' ? clockS : num);
    for (const key of CUM_SERIES) if (own(d, key)) series[key] = grid(d[key], 'cum');
    for (const key of RATE_SERIES) if (own(d, key)) series[key] = grid(d[key], 'rate');
    // any other numeric series as long as t[]: a level, carried forward
    for (const key of Object.keys(d)) {
      const arr = d[key];
      if (own(series, key) || key === 't' || key === 'events' || key === 'meta' || own(BREAKDOWNS, key) || !Array.isArray(arr) || arr.length !== n) continue;
      if (arr.length && arr.slice(0, Math.min(n, 50)).every((x) => typeof x === 'number' || typeof x === 'boolean' || x === null)) series[key] = grid(arr, 'level');
    }
    if (own(series, 'dps')) {
      const raw = series.dps;
      const sm = new Array(T + 1).fill(null);
      let acc = 0;
      const win = [];
      for (let s = 0; s <= end; s++) {
        const v = raw[s] || 0;
        win.push(v);
        acc += v;
        if (win.length > DPS_WINDOW) acc -= win.shift();
        sm[s] = acc / win.length;
      }
      series.dps_raw = raw;
      series.dps = sm;
    }
    deriveDifficulty(d, series, end, T);
    const bds = {};
    for (const name of Object.keys(BREAKDOWNS)) {
      const bd = d[name];
      if (!isObj(bd)) continue;
      const out = {};
      for (const key of Object.keys(bd)) if (Array.isArray(bd[key]) && bd[key].length === n) out[String(key)] = grid(bd[key], BREAKDOWNS[name]);
      bds[name] = out;
    }
    for (const name of Object.keys(d)) {
      const bd = d[name];
      if (own(BREAKDOWNS, name) || name === 'meta' || !isObj(bd) || !name.endsWith('_by')) continue;
      const out = {};
      for (const key of Object.keys(bd)) if (Array.isArray(bd[key]) && bd[key].length === n) out[String(key)] = grid(bd[key], 'level');
      if (Object.keys(out).length) bds[name] = out;
    }
    return [series, end, bds];
  }

  function bdEnd(g, name, i) {
    const a = (g.bds[name] || {})[i];
    if (!a) return 0;
    return a[g.end] || 0;
  }

  function medianSeries(grids, key, T) {
    const med = [], p10 = [], p90 = [], n = [];
    for (let s = 0; s <= T; s++) {
      const vals = sortNum(grids.filter((g) => own(g.series, key) && s < g.series[key].length && g.series[key][s] != null).map((g) => g.series[key][s]));
      n.push(vals.length);
      if (!vals.length) { med.push(null); p10.push(null); p90.push(null); continue; }
      med.push(r(pct(vals, 0.5)));
      p10.push(r(pct(vals, 0.1)));
      p90.push(r(pct(vals, 0.9)));
    }
    return { median: med, p10, p90, n };
  }

  /** sim_batch.markers: the stage starts and boss fights as medians over the runs that reached them; every death. */
  function markers(players) {
    const stages = new Map(), bosses = new Map(), deaths = [], revives = [];
    for (const d of players) {
      const seenStage = new Map(), occ = new Map(), cur = new Map();
      for (const e of Array.isArray(d.events) ? d.events : []) {
        if (!isObj(e)) continue;
        const kind = String(e.kind != null ? e.kind : '');
        const t = num(e.t, null);
        if (t === null) continue;
        if (kind === 'stage') {
          const st = Math.trunc(num(e.stage, 0));
          if (st > 1 && !seenStage.has(st)) seenStage.set(st, t);
        } else if (kind === 'boss_start') {
          const bid = String(e.id || 'boss');
          const nn = occ.get(bid) || 0;
          occ.set(bid, nn + 1);
          cur.set(bid, [bid, nn, t]);
          const key = bid + '\u0000' + nn;
          if (!bosses.has(key)) bosses.set(key, { id: bid, n: nn, start: [], end: [], mult: [], hp: [], fights: [] });
          const b = bosses.get(key);
          b.start.push(t);
          if (e.mult != null) b.mult.push(num(e.mult, 1.0));
          if (e.hp != null) b.hp.push(num(e.hp));
        } else if (kind === 'boss_end') {
          const bid = String(e.id || 'boss');
          const c = cur.has(bid) ? cur.get(bid) : [bid, Math.max(0, (occ.has(bid) ? occ.get(bid) : 1) - 1), null];
          cur.delete(bid);
          const key = c[0] + '\u0000' + c[1];
          if (!bosses.has(key)) bosses.set(key, { id: c[0], n: c[1], start: [], end: [], mult: [], hp: [], fights: [] });
          const b = bosses.get(key);
          b.end.push(t);
          if (c[2] !== null) b.fights.push(t - c[2]);
        } else if (kind === 'death') deaths.push(t);
        else if (kind === 'revive') revives.push(t);
      }
      for (const [st, t] of seenStage) {
        if (!stages.has(st)) stages.set(st, []);
        stages.get(st).push(t);
      }
    }
    const outSt = Array.from(stages.entries()).sort((a, b) => a[0] - b[0]).map(([st, v]) => ({ stage: st, t: r(median(v)), n: v.length, min: r(Math.min(...v)), max: r(Math.max(...v)) }));
    const blist = Array.from(bosses.values());
    const keyOf = (v) => median(v.start) || 1e9;
    blist.sort((a, b) => keyOf(a) - keyOf(b));
    const outB = blist.map((v) => ({ id: v.id, occurrence: v.n + 1, start: r(median(v.start)), end: r(median(v.end)), n: v.start.length, beaten: v.end.length,
      fight_s: v.fights.length ? r(median(v.fights)) : null, mult: r(median(v.mult)), hp: r(median(v.hp)) }));
    return { stages: outSt, bosses: outB, deaths: sortNum(deaths.map(r)), revives: sortNum(revives.map(r)) };
  }

  /** A name for an id the records do not name (sim_batch.content_names' fallback: "red_goblin" -> "Red goblin"). */
  function nameOf(id, names) {
    if (names && names[id]) return String(names[id]);
    if (SOURCE_WORDS[id]) return SOURCE_WORDS[id];
    const s = String(id).replace(/_/g, ' ');
    return s.charAt(0).toUpperCase() + s.slice(1).toLowerCase();
  }

  function runRate(rec, m) {
    if (rec.rate) return Number(rec.rate);
    const play = num(m.end_t), wall = num(m.wall_s), boot = num(m.boot_s);
    if (play >= 30 && wall - boot > 1) return play / (wall - boot);
    return null;
  }

  /** sim_batch.aggregate. `players`: [{k, d (the player's data, or null for a failed one), rec ({seed, end_reason, end_t,
   *  wall_s, problem})}]; `settings`: at least {limit, hero}; `meta` goes into the result; `names` {id: display name}
   *  (the records' own; sim_batch reads the content folders). */
  function aggregate(players, settings, meta, names) {
    const st = Object.assign({ hero: 'drifter', limit: 1500 }, settings || {});
    const ok = players.filter((p) => p.d != null);
    const limit = Math.trunc(num((settings || {}).limit, 1500));
    let T = 0;
    for (const p of ok) {
      const tt = (Array.isArray(p.d.t) ? p.d.t : []).map((x) => pyRound(num(x), 0));
      if (tt.length) T = Math.max(T, Math.min(limit, Math.max(...tt)));
    }
    const grids = [], ends = [];
    for (const p of ok) {
      const [series, end, bds] = playerGrid(p.d, T);
      grids.push({ k: p.k, series, end, bds, d: p.d });
      ends.push(end);
    }
    const nAll = grids.length;
    const playing = [];
    for (let s = 0; s <= T; s++) playing.push(ends.filter((e) => s <= e).length);
    const keys = new Set();
    for (const g of grids) for (const k of Object.keys(g.series)) keys.add(k);
    const outSeries = {};
    for (const key of Array.from(keys).sort(cmpStr)) {
      if (key === 'deaths') continue;
      if (MEDIAN_SERIES.includes(key)) { outSeries[key] = medianSeries(grids, key, T); continue; }
      const mean = [], p10 = [], p90 = [], med = [];
      const band = BAND_SERIES.includes(key);
      const isMed = key === 'clock' || key === 'stage';
      for (let s = 0; s <= T; s++) {
        const vals = [];
        for (const g of grids) if (own(g.series, key) && g.series[key][s] != null) vals.push(g.series[key][s]);
        if (!vals.length) {
          mean.push(null);
          if (band) { p10.push(null); p90.push(null); }
          if (isMed) med.push(null);
          continue;
        }
        let sum = 0;
        for (const v of vals) sum += v;
        mean.push(r(sum / vals.length));
        if (band || isMed) {
          const sv = sortNum(vals);
          if (band) { p10.push(r(pct(sv, 0.1))); p90.push(r(pct(sv, 0.9))); }
          if (isMed) med.push(r(pct(sv, 0.5)));
        }
      }
      let rec = { mean };
      if (band) { rec.p10 = p10; rec.p90 = p90; }
      if (isMed) rec = { median: med };
      outSeries[key] = rec;
    }
    // deaths: every player at every second, an ended run keeping its last count
    if (grids.some((g) => own(g.series, 'deaths'))) {
      const dm = [];
      for (let s = 0; s <= T; s++) {
        let tot = 0;
        for (const g of grids) {
          const arr = g.series.deaths;
          if (!arr) continue;
          tot += arr[Math.min(s, g.end)] || 0;
        }
        dm.push(r(tot / Math.max(1, nAll)));
      }
      outSeries.deaths = { mean: dm, over: 'all' };
    }
    // the breakdowns: means over the players still playing (an id a player never had counts 0 for him)
    const outBd = {};
    const allIds = new Set();
    const bdNames = new Set();
    for (const g of grids) for (const nm of Object.keys(g.bds)) bdNames.add(nm);
    for (const name of Array.from(bdNames).sort(cmpStr)) {
      const ids = new Set();
      for (const g of grids) for (const i of Object.keys(g.bds[name] || {})) ids.add(i);
      const means = {};
      for (const i of ids) {
        const arr = [];
        for (let s = 0; s <= T; s++) {
          let n = 0, tot = 0;
          for (const g of grids) {
            if (s > g.end) continue;
            n += 1;
            const a = (g.bds[name] || {})[i];
            if (a != null && a[s] != null) tot += a[s];
          }
          arr.push(n ? r(tot / n) : null);
        }
        means[i] = arr;
      }
      const kind = BREAKDOWNS[name] || 'level';
      const score = {};
      for (const i of ids) {
        let sc = 0;
        if (kind === 'cum') { for (const g of grids) sc += bdEnd(g, name, i); }
        else { for (const v of means[i]) if (v != null) sc += v; }
        score[i] = sc;
      }
      const order = Array.from(ids).sort((a, b) => (score[b] - score[a]) || cmpStr(a, b));
      const scoreOut = {};
      for (const i of ids) scoreOut[i] = r(score[i] / Math.max(1, nAll));
      outBd[name] = { kind, order, mean: means, score: scoreOut };
      for (const i of ids) allIds.add(i);
    }
    // per player: how his run went
    const plist = [];
    for (const p of players) {
      const d = p.d, rec = p.rec || {};
      const m = (d && d.meta) || {};
      const g = grids.find((x) => x.k === p.k) || null;
      const atEnd = (key) => (g === null || !own(g.series, key) ? null : r(g.series[key][g.end]));
      const ev = (d && Array.isArray(d.events)) ? d.events : [];
      let dmg = null;
      if (g) { let s = 0; for (const i of Object.keys(g.bds.dmg_by || {})) s += bdEnd(g, 'dmg_by', i); dmg = r(s); }
      plist.push({ k: p.k, seed: own(rec, 'seed') ? rec.seed : null, ok: d != null,
        end_reason: String(m.end_reason || rec.end_reason || (d ? '' : 'failed')),
        end_t: d ? r(num(m.end_t, g ? g.end : 0)) : r(rec.end_t || 0),
        wall_s: d ? r(num(m.wall_s, rec.wall_s || 0)) : r(rec.wall_s || 0),
        boot_s: r(rec.boot_s != null ? rec.boot_s : (own(m, 'boot_s') ? m.boot_s : null)),
        rate: r(runRate(rec, m)),
        problem: d == null ? (own(rec, 'problem') ? rec.problem : '') : '',
        deaths: atEnd('deaths'), revives: ev.filter((e) => isObj(e) && e.kind === 'revive').length,
        level: atEnd('level'), kills: atEnd('kills'), gold: atEnd('gold_total'), xp: atEnd('xp_total'), dmg,
        fps: own(m, 'fps') ? m.fps : null, build: String(m.build_text || ''), assists: own(m, 'assists') ? m.assists : null,
        end_stage: own(m, 'end_stage') ? m.end_stage : null, endless_wave: own(m, 'endless_wave') ? m.endless_wave : null, talents: m.talents || {},
        chests: atEnd('chests'), powerups: atEnd('powerups'), totems: atEnd('totems') });
    }
    const mk = markers(ok.map((p) => p.d));
    const nm = {};
    for (const i of Array.from(allIds).concat(mk.bosses.map((b) => b.id), [st.hero])) if (i) nm[i] = nameOf(i, names);
    const reached = plist.filter((p) => p.ok && num(p.end_t) >= limit - 1.5).length;
    const endMean = (key) => {
      const vals = plist.filter((p) => p.ok && p[key] != null).map((p) => num(p[key]));
      if (!vals.length) return null;
      let s = 0;
      for (const v of vals) s += v;
      return r(s / vals.length);
    };
    const summary = { players: players.length, ok: nAll, failed: players.length - nAll, reached_limit: reached,
      median_end_t: r(median(plist.filter((p) => p.ok).map((p) => num(p.end_t)))),
      deaths_mean: endMean('deaths'), revives_mean: endMean('revives'), kills_mean: endMean('kills'),
      level_mean: endMean('level'), gold_mean: endMean('gold'), xp_mean: endMean('xp'), dmg_mean: endMean('dmg'),
      chests_mean: endMean('chests'), powerups_mean: endMean('powerups'), totems_mean: endMean('totems'),
      bosses: mk.bosses.map((b) => ({ id: b.id, occurrence: b.occurrence, reached: b.n, beaten: b.beaten, fight_s: b.fight_s, mult: b.mult })) };
    const tt = [];
    for (let s = 0; s <= T; s++) tt.push(s);
    const res = { schema: SCHEMA, meta: Object.assign({}, meta || {}), settings: st, names: nm, t: tt, playing, series: outSeries,
      breakdowns: outBd, markers: mk, players: plist, summary,
      rules: { dps_window: DPS_WINDOW, rate_window: RATE_WINDOW, trouble: TROUBLE_FRAC, bands: BAND_SERIES.slice(), medians: MEDIAN_SERIES.slice(), fold: FOLD_DEFAULT } };
    if (!own(res.meta, 'hero_name')) res.meta.hero_name = nm[st.hero] || st.hero;
    const ms = ok.map((p) => p.d.meta || {});
    const unl = Array.from(new Set(ms.filter((m) => m.unlocks).map((m) => String(m.unlocks)))).sort(cmpStr);
    if (unl.length) res.meta.unlocks = unl.length === 1 ? unl[0] : 'mixed';
    res.meta.assists = ms.reduce((a, m) => a + Math.trunc(num(m.assists, 0)), 0);
    if (ms.length && !ms.some((m) => m.synthetic)) res.meta.sim_mode = ms.some((m) => !!m.fast);
    return res;
  }

  // ------------------------------------------------------------------ a run record as one player (sim_run.gd series())

  /** Godot's snappedf: floor(v / step + 0.5) * step. */
  function snapped(v, step) { return Math.floor(v / step + 0.5) * step; }
  const fl = (v, d) => { const f = Number(v); return v == null || v === '' || !isFinite(f) ? (d || 0) : f; };
  const int = (v, d) => Math.trunc(fl(v, d));

  /** sim_run.gd _step: every id seen so far gets this row's value (cum: the running sum), a new id zeros before it. */
  function step(byId, acc, vals, i, cum, snap) {
    for (const k of Object.keys(vals)) {
      if (!own(byId, k)) byId[k] = new Array(i).fill(0);
    }
    for (const id of Object.keys(byId)) {
      const v = own(vals, id) ? vals[id] : 0;
      const a = byId[id];
      if (!cum) a.push(int(v));
      else if (snap) { const f = fl(acc[id], 0) + fl(v); acc[id] = f; a.push(snapped(f, 0.1)); }
      else { const n = int(acc[id], 0) + int(v); acc[id] = n; a.push(n); }
    }
  }

  /** sim_run.gd events_out: the events the charts mark, renamed to say what their number is, then the end. */
  function eventsOut(rec, toolEvents, endEv) {
    const out = [];
    for (const e of rec || []) {
      if (!isObj(e)) continue;
      const kind = String(e.kind != null ? e.kind : '');
      const base = { t: fl(e.t), clock: fl(e.clock), kind };
      if (kind === 'level') base.level = int(e.level);
      else if (kind === 'death') { base.killer = String(e.id != null ? e.id : ''); base.hit = String(e.hit != null ? e.hit : ''); }
      else if (kind === 'revive') base.via = String(e.id != null ? e.id : '');
      else if (kind === 'boss_start') { base.id = String(e.id != null ? e.id : ''); for (const k of ['hp', 'mult', 'dps', 'ref']) if (own(e, k)) base[k] = e[k]; }
      else if (kind === 'boss_end') base.id = String(e.id != null ? e.id : '');
      else if (kind === 'stage') base.stage = int(e.level);
      else if (kind === 'wave') base.wave = int(e.level);
      else continue;
      out.push(base);
    }
    for (const e of toolEvents || []) out.push(e);
    if (endEv && Object.keys(endEv).length) out.push(endEv);
    const idx = out.map((_, i) => i);
    idx.sort((a, b) => { const ta = Number(out[a].t), tb = Number(out[b].t); return ta !== tb ? (ta < tb ? -1 : 1) : a - b; });
    return idx.map((i) => out[i]);
  }

  /** sim_run.gd series(rows, rec, tool_events, end_ev, evo_ids): the per-player series of keys_SIMRUN.md. */
  function series(rows, rec, toolEvents, endEv, evoIds) {
    const evo = evoIds || {};
    const S = { t: [], clock: [], stage: [], phase: [], hp: [], hp_max: [], dps: [], est: [], alive: [], cap: [], press_hp: [], press_dmg: [],
      boss_hp: [], boss_hp_abs: [], near3: [], near6: [], hits: [], spawned: [], mult_hp: [], mult_dmg: [] };
    const tookBy = {}, healedBy = {}, tookAcc = {}, healedAcc = {};
    const heldBy = { weapons: [], evolutions: [], lines: [], passives: [], perks: [] };
    const held = { weapons: 0, evolutions: 0, lines: 0, passives: 0, perks: 0 };
    let mHp = 1.0, mDmg = 1.0;
    const goldTotal = [], gold = [], dmgTotal = [], kills = [], level = [], xpTotal = [], took = [], healed = [], deaths = [];
    const aliveBy = {}, goldBy = {}, dmgBy = {}, killsBy = {}, goldAcc = {}, dmgAcc = {}, killsAcc = {};
    const fallT = [];
    for (const e of rec || []) if (isObj(e) && String(e.kind) === 'death') fallT.push(fl(e.t));
    let fi = 0, gsum = 0, dsum = 0, lastT = 0;
    rows.forEach((r0, i) => {
      const row = isObj(r0) ? r0 : {};
      const rt = fl(row.t);
      const ti = Math.max(Math.trunc(Math.ceil(rt - 0.05)), lastT + 1);
      lastT = ti;
      S.t.push(ti);
      S.clock.push(snapped(fl(row.clock), 0.1));
      S.stage.push(int(row.stage, 1));
      S.phase.push(int(row.phase));
      S.hp.push(snapped(fl(row.hp), 0.1));
      S.hp_max.push(snapped(fl(row.hp_max), 0.1));
      let second = 0;
      const dm = isObj(row.dmg) ? row.dmg : {};
      for (const k of Object.keys(dm)) second += fl(dm[k]);
      dsum += second;
      S.dps.push(snapped(second, 0.1));
      dmgTotal.push(snapped(dsum, 0.1));
      step(dmgBy, dmgAcc, dm, i, true, true);
      S.est.push(snapped(fl(row.est_total), 0.1));
      S.alive.push(int(row.alive));
      S.cap.push(int(row.cap));
      S.press_hp.push(snapped(fl(row.press_hp), 0.1));
      S.press_dmg.push(snapped(fl(row.press_dmg), 0.1));
      S.boss_hp.push(fl(row.boss_hp));
      S.boss_hp_abs.push(fl(row.boss_now));
      S.near3.push(int(row.near3));
      S.near6.push(int(row.near6));
      S.hits.push(int(row.hits));
      let spN = 0;
      const sp = isObj(row.spawned) ? row.spawned : {};
      for (const k of Object.keys(sp)) spN += int(sp[k]);
      S.spawned.push(spN);
      if (isObj(row.mults)) {
        const mu = row.mults;
        mHp = fl(mu.stage, 1.0) * fl(mu.hp_t, 1.0) * fl(mu.lvl_hp, 1.0);
        mDmg = fl(mu.stage, 1.0) * fl(mu.dmg_t, 1.0) * fl(mu.lvl_dmg, 1.0);
      }
      S.mult_hp.push(snapped(mHp, 0.001));
      S.mult_dmg.push(snapped(mDmg, 0.001));
      step(tookBy, tookAcc, isObj(row.took) ? row.took : {}, i, true, true);
      const hb = isObj(row.healed_by) ? Object.assign({}, row.healed_by) : {};
      if (fl(row.regen) !== 0) hb.regen = fl(hb.regen) + fl(row.regen);
      step(healedBy, healedAcc, hb, i, true, true);
      if (Array.isArray(row.weapons)) {
        let nw = 0, ne = 0;
        for (const w of row.weapons) {
          if (isObj(w) && evo[String(w.id != null ? w.id : '')]) ne += 1;
          else nw += 1;
        }
        held.weapons = nw;
        held.evolutions = ne;
      }
      if (isObj(row.lines)) held.lines = Object.keys(row.lines).length;
      if (isObj(row.passives)) held.passives = Object.keys(row.passives).length;
      if (Array.isArray(row.perks)) held.perks = row.perks.length;
      for (const k of Object.keys(held)) heldBy[k].push(Math.trunc(held[k]));
      step(aliveBy, {}, isObj(row.alive_by) ? row.alive_by : {}, i, false, false);
      const gi = isObj(row.gold_in) ? row.gold_in : {};
      for (const k of Object.keys(gi)) gsum += int(gi[k]);
      goldTotal.push(gsum);
      step(goldBy, goldAcc, gi, i, true, false);
      gold.push(int(row.gold));
      kills.push(int(row.kills));
      step(killsBy, killsAcc, isObj(row.killed) ? row.killed : {}, i, true, false);
      level.push(int(row.level, 1));
      xpTotal.push(snapped(fl(row.xp_total), 0.1));
      let lost = 0;
      const tk = isObj(row.took) ? row.took : {};
      for (const k of Object.keys(tk)) lost += fl(tk[k]);
      took.push(snapped(lost, 0.1));
      healed.push(snapped(fl(row.healed) + fl(row.regen), 0.1));
      while (fi < fallT.length && fallT[fi] <= rt + 0.001) fi += 1;
      deaths.push(fi);
    });
    const out = Object.assign({}, S);
    out.sums = { rows: rows.length, deaths: fallT.length, gold_total: gsum };
    Object.assign(out, { took_by: tookBy, healed_by: healedBy, held_by: heldBy, alive_by: aliveBy, gold_total: goldTotal, gold, gold_by: goldBy,
      dmg_total: dmgTotal, dmg_by: dmgBy, kills, kills_by: killsBy, level, xp_total: xpTotal, took, healed, deaths });
    // pass 82 (lane STATS): chests, power-ups and totems so far at each row (sim_run.gd series()'s pickup counts)
    Object.assign(out, SM.pickupCounts(rec, rows.map((r0) => fl(isObj(r0) ? r0.t : 0))));
    out.events = eventsOut(rec, toolEvents, endEv);
    return out;
  }

  /** The evolutions among a record's weapons (sim_run.gd asks the Registry; a record names them by its evolution events). */
  function evoIdsOf(record) {
    const out = {};
    for (const e of (record && record.events) || []) if (isObj(e) && (e.kind === 'evolution') && e.id) out[String(e.id)] = true;
    return out;
  }

  /** A run record (local or remote, schema 1 or 2) as one player of the Sim's schema: the series of sim_run.gd's
   *  series() from its rows and events, and a meta from its header in the runner's words (end_reason = the record's
   *  result, end_t = its play length, ...). */
  function fromRecord(record, opts) {
    const o = opts || {};
    const rec = record || {};
    const rows = Array.isArray(rec.samples) ? rec.samples : [];
    const events = Array.isArray(rec.events) ? rec.events : [];
    const end = { t: snapped(fl(rec.length, rows.length ? fl(rows[rows.length - 1].t) : 0), 0.1), clock: snapped(fl(rec.clock), 0.1), kind: 'end', reason: String(rec.result || '') };
    const out = series(rows, events, [], o.noEnd ? {} : end, o.evoIds || evoIdsOf(rec));
    const sums = out.sums;
    delete out.sums;
    const tal = {}, forms = {};
    for (const id of Object.keys(isObj(rec.talents) ? rec.talents : {})) {
      const p = rec.talents[id];
      if (Array.isArray(p) && p.length) { tal[id] = p.length; forms[id] = p.map((x) => (Number(x) === 1 ? 'B' : 'A')).join(''); }
    }
    const revives = {};
    for (const e of events) if (isObj(e) && e.kind === 'revive') { const k = String(e.id || 'other'); revives[k] = (revives[k] || 0) + 1; }
    // a key an older record never wrote is left out, so its chart hides instead of drawing zeros (the recorder leaves a
    // zero out of a row, so "never on any row" is "not recorded"): xp_total, near3/near6, boss_now (pass 77), lines
    // (schema 2: before it they were among the passives), gold_in (pass 61)
    const seen = (k) => rows.some((r0) => isObj(r0) && own(r0, k));
    if (!seen('xp_total')) delete out.xp_total;
    if (!seen('near3')) delete out.near3;
    if (!seen('near6')) delete out.near6;
    if (!seen('boss_now')) delete out.boss_hp_abs;
    if (!seen('lines')) delete out.held_by.lines;
    if (!seen('gold_in')) { delete out.gold_total; delete out.gold_by; }
    const dmgTotal = out.dmg_total.length ? out.dmg_total[out.dmg_total.length - 1] : 0;
    out.meta = { schema: SCHEMA, source: 'record', record_schema: Number(rec.schema) || 1, hero: String(rec.hero || ''), hero_name: String(rec.hero_name || rec.hero || ''),
      hero_look: String(rec.hero_look || ''), start_weapon: String((rec.timeline && rec.timeline.start_weapon) || ''), seed: rec.seed,
      map: String(rec.map || ''), map_rev: rec.map_rev != null ? rec.map_rev : '', version: String(rec.version || ''), result: String(rec.result || ''),
      end_reason: String(rec.result || ''), end_t: snapped(fl(rec.length, end.t), 0.1), end_clock: snapped(fl(rec.clock), 0.1),
      end_stage: int(rec.stage, 1), end_level: int(rec.level, 1), endless_wave: int(rec.endless_wave), deaths: sums.deaths, revives,
      kills: int(rec.kills), gold_total: sums.gold_total, xp_total: out.xp_total && out.xp_total.length ? out.xp_total[out.xp_total.length - 1] : 0, dmg_total: dmgTotal,
      build_text: String(rec.build_text || ''), rows: sums.rows, started: String(rec.started || ''), stamp: String(rec.stamp || ''),
      run_id: String(rec.run_id || ''), talents: tal, talent_forms: forms, tool: !!rec.tool, headless: !!rec.headless,
      dev: !!(rec.settings && rec.settings.dev), device: String(rec.device || ''), platform: String(rec.platform || '') };
    if (o.player) out.meta.player = o.player;
    return out;
  }

  return { SCHEMA, DPS_WINDOW, RATE_WINDOW, TROUBLE_FRAC, LEVEL_SERIES, CUM_SERIES, RATE_SERIES, BAND_SERIES, MEDIAN_SERIES, BREAKDOWNS,
    pyRound, fracBits, num, clockS, r, pct, median, rolling, playerGrid, markers, aggregate, nameOf,
    snapped, step, eventsOut, series, evoIdsOf, fromRecord };
})();

if (typeof module !== 'undefined' && module.exports) module.exports = SimAvg;
