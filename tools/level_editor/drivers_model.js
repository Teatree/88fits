'use strict';
// Pass 93 (lane PREVIEW): the page-free maths of the driver viewer (drivers.js) and of the frame pickers (death_keep):
// which view a field previews, the frame list a picker edits (toggled, kept in order, clamped to the clip, read from
// typed text), the frames the result plays, stepping and scrubbing, the library's filter and sort, a size in words.
// selftest_PREVIEW93.py runs it under Node. A frame index is the number in the file name (ctl_07.png is frame 7, 0-based),
// the same number death_keep holds and gen_ctl reads (tools/gen_ctl.py: keyed[k] for k in keep).
const DriversModel = (() => {
  const VIEWS = ['front', 'fd', 'side', 'bd', 'back'];
  const VIEW_LABEL = { front: 'front', fd: 'front ¾', side: 'side', bd: 'back ¾', back: 'back' };
  // death_keep's default in tools/gen_ctl.py and methods.json
  const DEATH_KEEP_DEFAULT = [1, 4, 7, 10, 13, 16, 20, 24];
  const SPEEDS = [2, 4, 6, 8, 10, 12, 16, 24];

  const isInt = (v) => typeof v === 'number' && isFinite(v) && Math.floor(v) === v;

  /** The view a driver field previews: the view its key names (pose_drivers.back -> back), else the field's own
   *  (pose = a creature's back clip, pose_front, death_drivers and death_keep = the front, drivers = the side). */
  function viewOfKey(key) {
    const k = String(key || '');
    const last = k.split('.').pop();
    if (VIEWS.includes(last)) return last;
    if (/(^|\.)pose_front$/.test(k)) return 'front';
    if (/(^|\.)pose$/.test(k)) return 'back';
    if (/(^|\.)(death_drivers|death_keep)$/.test(k)) return 'front';
    return 'side';
  }

  /** The view to show of a driver: `want` when it has it, else side, front, then its first. */
  function pickView(views, want) {
    const vs = Array.isArray(views) ? views : [];
    if (want && vs.includes(want)) return want;
    for (const v of ['side', 'front', 'fd', 'bd', 'back']) if (vs.includes(v)) return v;
    return vs[0] || null;
  }

  /** A frame list from what a field holds (an array, a JSON text, "1 4 7", "1,4,7"): {list, error}. Kept in the order
   *  given (the result plays them in that order), integers only. */
  function parseList(v) {
    if (v == null || v === '') return { list: null, error: '' };
    let arr = v;
    if (typeof v === 'string') {
      const t = v.trim();
      if (t === '') return { list: null, error: '' };
      try { arr = JSON.parse(t); } catch (_) { arr = t.split(/[\s,;]+/).filter((x) => x !== '').map(Number); }
    }
    if (typeof arr === 'number') arr = [arr];
    if (!Array.isArray(arr)) return { list: null, error: 'not a list of frame numbers' };
    const out = [];
    for (const x of arr) {
      const n = typeof x === 'string' && x.trim() !== '' ? Number(x) : x;
      if (!isInt(n) || n < 0) return { list: null, error: `${JSON.stringify(x)} is not a frame number (0 or more)` };
      out.push(n);
    }
    return { list: out, error: '' };
  }

  /** The list with frame i in or out: added in its place by number (a death plays forward), taken out wherever it is. */
  function toggle(list, i) {
    const cur = Array.isArray(list) ? list.slice() : [];
    const at = cur.indexOf(i);
    if (at >= 0) { cur.splice(at, 1); return cur; }
    let k = cur.findIndex((x) => x > i);
    if (k < 0) k = cur.length;
    cur.splice(k, 0, i);
    return cur;
  }

  /** The frames of `list` the clip has (0 .. total-1), in their order, each once; and the ones it does not have. */
  function clamp(list, total) {
    const ok = [];
    const out = [];
    const seen = new Set();
    for (const i of Array.isArray(list) ? list : []) {
      if (!isInt(i) || i < 0 || (total > 0 && i >= total)) { out.push(i); continue; }
      if (seen.has(i)) continue;
      seen.add(i);
      ok.push(i);
    }
    return { list: ok, outside: out };
  }

  /** n frames spread evenly over 0 .. total-1, the last one always in (the dead pose) and the first one left out
   *  (the standing pose the walk already shows): 8 of 25 -> [3, 6, 9, 12, 15, 18, 21, 24]. */
  function evenPick(total, n) {
    const T = Math.max(0, Math.floor(total));
    const N = Math.max(0, Math.min(Math.floor(n), T));
    if (!N) return [];
    if (N >= T) return Array.from({ length: T }, (_, k) => k);
    const out = [];
    for (let k = 1; k <= N; k++) out.push(Math.round((T - 1) * k / N));
    return Array.from(new Set(out));
  }

  /** What the result plays: the kept frames in their order, clamped to the clip; empty when nothing is kept. */
  function playOrder(list, total) { return clamp(list, total).list; }

  /** The next position when stepping d (+1 / -1) through n frames: wraps when `loop`, else stops at the ends. */
  function step(pos, n, d, loop) {
    if (n <= 0) return 0;
    const p = pos + (d > 0 ? 1 : -1);
    if (loop) return ((p % n) + n) % n;
    return Math.max(0, Math.min(n - 1, p));
  }

  /** "12.4 MB", "830 KB", "512 B". */
  function sizeText(b) {
    const n = Number(b) || 0;
    if (n >= 1024 * 1024) return `${(n / 1024 / 1024).toFixed(n >= 100 * 1024 * 1024 ? 0 : 1)} MB`;
    if (n >= 1024) return `${Math.round(n / 1024)} KB`;
    return `${n} B`;
  }

  /** "2026-10-19 14:20" from unix seconds (local time). */
  function dateText(sec) {
    if (!sec) return '';
    const d = new Date(Number(sec) * 1000);
    const p = (x) => String(x).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
  }

  /** The kind words of a driver: OpenPose / depth, and death when it is one. */
  function kindText(d) {
    const k = d && d.kind === 'depth' ? 'depth' : 'OpenPose';
    return d && d.death ? `${k} · death` : k;
  }

  /** The library filtered: `q` matches the name, what made it, its source, its clip and who uses it (words, any order);
   *  `kind` all | pose | depth | death | used | unused. */
  function filter(list, q, kind) {
    const words = String(q || '').toLowerCase().split(/\s+/).filter(Boolean);
    return (Array.isArray(list) ? list : []).filter((d) => {
      if (kind === 'pose' && d.kind === 'depth') return false;
      if (kind === 'depth' && d.kind !== 'depth') return false;
      if (kind === 'death' && !d.death) return false;
      if (kind === 'used' && !(d.used_by && d.used_by.length)) return false;
      if (kind === 'unused' && d.used_by && d.used_by.length) return false;
      if (!words.length) return true;
      const hay = [d.name, d.made, d.source, d.action, d.notes, (d.views || []).join(' '),
        (d.used_by || []).map((u) => `${u.id} ${u.code} ${u.key}`).join(' ')].join(' ').toLowerCase();
      return words.every((w) => hay.includes(w));
    });
  }

  /** The library sorted by name, newest first or biggest first. */
  function sort(list, by) {
    const out = (Array.isArray(list) ? list : []).slice();
    if (by === 'date') out.sort((a, b) => (Number(b.mtime) || 0) - (Number(a.mtime) || 0) || String(a.name).localeCompare(String(b.name)));
    else if (by === 'size') out.sort((a, b) => (Number(b.size) || 0) - (Number(a.size) || 0) || String(a.name).localeCompare(String(b.name)));
    else out.sort((a, b) => String(a.name).localeCompare(String(b.name)));
    return out;
  }

  /** "front 25 · fd 25 · side 25" (the frames each view has on disk). */
  function countsText(d) {
    const c = d && d.counts ? d.counts : {};
    return (d && Array.isArray(d.views) ? d.views : []).map((v) => `${VIEW_LABEL[v] || v} ${c[v] != null ? c[v] : '?'}`).join(' · ');
  }

  /** "enemy bull_beetle BB-C (played) · death_drivers". */
  function usedText(u) {
    return `${u.kind} ${u.id}${u.code ? ' ' + u.code : ''}${u.played ? ' (played)' : ''} · ${u.key}`;
  }

  /** The frame URL pattern of a listing entry's view (frames_url "/dl/drivers/<name>/<view>/" + frame_pattern). */
  function framePattern(d, view) {
    let base = String(d.frames_url || `/dl/drivers/${d.name}/<view>/`);
    base = base.includes('<view>') ? base.replace('<view>', view) : base.replace(/\/?$/, '/') + view + '/';
    return base + (d.frame_pattern || (d.kind === 'depth' ? 'ctl_%02d.png' : 'driver_%02d.png'));
  }

  /** The URL of frame i (its number) from a pattern. */
  function frameUrl(pattern, i) {
    return String(pattern).replace(/%0(\d)d/, (m, w) => String(i).padStart(Number(w), '0')).replace(/%d/, String(i));
  }

  /** The keep list's words: "8 frames: 1 4 7 10 13 16 20 24 (the default)". */
  function keepText(list, dflt) {
    if (!Array.isArray(list) || !list.length) return Array.isArray(dflt) && dflt.length ? `the default: ${dflt.join(' ')}` : 'none';
    const same = Array.isArray(dflt) && dflt.length === list.length && dflt.every((x, k) => x === list[k]);
    return `${list.length} frame${list.length === 1 ? '' : 's'}: ${list.join(' ')}${same ? ' (the default)' : ''}`;
  }

  /** Whether a look's painted death (its cycle.json ctl_dir, "tools/dl/drivers/<folder>/front") was walked along
   *  driver `name` (or its softened copy <name>_soft<r>[b]): a death painted on another driver is not shown as this one's. */
  function paintedFits(ctlDir, name) {
    if (!ctlDir || !name) return !ctlDir;
    const m = /(?:^|\/)drivers\/([^/]+)\/[^/]+\/?$/.exec(String(ctlDir).split('\\').join('/'));
    if (!m) return false;
    const folder = m[1];
    return folder === name || (folder.startsWith(name + '_soft') && /^\d+b?$/.test(folder.slice(name.length + 5)));
  }

  const api = { paintedFits, VIEWS, VIEW_LABEL, DEATH_KEEP_DEFAULT, SPEEDS, viewOfKey, pickView, parseList, toggle, clamp, evenPick, playOrder, step, sizeText, dateText, kindText, filter, sort, countsText, usedText, framePattern, frameUrl, keepText };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  return api;
})();
