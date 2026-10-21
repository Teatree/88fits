'use strict';
// Pass 95 (lane VACE): the page-free maths of the Frames view (frames.js): the slot selection (click, shift-click a
// range), the playlist the preview plays, the repair window (a mirror of tools/vace_repair.window_plan, so the page
// says what goes in before the job is queued), the badges of a slot (staged, pinned, the installed strip differing,
// the flags), what a version is in words, the compatibility warnings of another look's frames, a frame list typed.
// selftest_VACE95.py runs it under Node. A slot is a frame's index in its animation (0-based), the number on the sheet.
const FramesModel = (() => {
  const VIEWS = ['front', 'fd', 'side', 'bd', 'back'];
  const VIEW_LABEL = { front: 'front', fd: 'front ¾', side: 'side', bd: 'back ¾', back: 'back' };
  const ANIM_LABEL = { idle: 'idle', run: 'run', attack: 'attack', hit: 'hit', die: 'die', turn: 'turn', cheer: 'cheer' };
  const SPEEDS = [2, 4, 6, 8, 10, 12, 14, 16, 20, 24, 36];
  const ZOOMS = [1, 2, 3];
  const SOURCE_TEXT = { installed: 'the installed frame (the strip)', reroll: 're-rolled by a job (the strip)', vace: 'painted anew by VACE', copied: 'copied from another look', repaint: 'repainted', neighbour: 'filled from a neighbour',
    old_roll: 'an old roll (a generation moved aside)', archived: 'an archived strip' };   // pass 96: the marks the picker shows where the store has them (AN-06's import is Phase 4)
  // pass 96 (lane PAGE, Garry's decision 1): the frame label everywhere, the JS twin of frames_store.label_of
  const VIEW_WORD = { front: 'Front', fd: 'Front ¾', side: 'Side', bd: 'Back ¾', back: 'Back' };
  const SOURCE_OPTIONS = [{ v: '', label: 'any source' }, { v: 'installed', label: 'installed' }, { v: 'reroll', label: 're-rolled' }, { v: 'vace', label: 'VACE' }, { v: 'copied', label: 'copied' },
    { v: 'repaint', label: 'repainted' }, { v: 'neighbour', label: 'filled from a neighbour' }, { v: 'old_roll', label: 'old roll' }, { v: 'archived', label: 'archived' }];
  const TIME_OPTIONS = [{ v: 0, label: 'any time' }, { v: 1, label: 'the last day' }, { v: 7, label: 'the last week' }, { v: 30, label: 'the last month' }];
  const SOURCE_MARK = { old_roll: 'old roll', archived: 'archived' };

  const isInt = (v) => typeof v === 'number' && isFinite(v) && Math.floor(v) === v;

  /** `SP-A / Run / Side / Frame 07 / v2`: the slot zero-padded (the sheet's 0-based number), the version's n; without n the slot's name. */
  function frameLabel(code, base, view, slot, n) {
    const parts = [String(code || '?')];
    if (base) parts.push(String(base).charAt(0).toUpperCase() + String(base).slice(1));
    if (view) parts.push(VIEW_WORD[view] || (String(view).charAt(0).toUpperCase() + String(view).slice(1)));
    if (slot != null && isFinite(Number(slot))) parts.push(`Frame ${String(Number(slot)).padStart(2, '0')}`);
    if (n != null && isFinite(Number(n))) parts.push(`v${Number(n)}`);
    return parts.join(' / ');
  }
  /** A served version's name (the route gives `name`; else built from the group). */
  function nameOf(v, g) { return (v && v.name) || frameLabel(g && g.code, g && g.base, g && g.view, v && v.slot, v && v.n); }
  /** The mark on a version from where it came: 'old roll', 'archived', or '' (removed looks are marked on the look). */
  function sourceMark(v) { return SOURCE_MARK[v && v.source] || ''; }

  /** The picker's filters on one group's versions (pass 96, AN-07: look, time, source, only raw; newest first).
   *  f: {source: '' | key, days: 0 | n, raw: bool}; `now` in ms (tests pass one). */
  function filterVersions(list, f, now) {
    const o = f || {};
    const t0 = o.days > 0 ? (now || Date.now()) - o.days * 86400000 : null;
    return (Array.isArray(list) ? list.slice() : []).filter((v) => {
      if (o.source && v.source !== o.source) return false;
      if (o.raw && !(v.raw || v.space === 'raw')) return false;
      if (t0 != null) { const t = v.time ? new Date(String(v.time).replace(' ', 'T')).getTime() : NaN; if (isNaN(t) || t < t0) return false; }
      return true;
    }).sort((a, b) => {
      const ta = a.time ? String(a.time) : '', tb = b.time ? String(b.time) : '';
      if (ta !== tb) return tb.localeCompare(ta);
      return (Number(b.n) || 0) - (Number(a.n) || 0);
    });
  }

  /** The confirm box's lines (pass 96, decision 5): one per change, `Run / Side / Frame 07 <- SP-A / Run / Side / Frame 07 / v2 (VACE)`,
   *  with the flag deltas in words; and the box's summary. */
  function batchLines(b) {
    const items = b && Array.isArray(b.items) ? b.items : [];
    return items.map((i) => {
      const to = i.to || {};
      const src = { installed: 'the strip', reroll: 're-rolled', vace: 'VACE', copied: 'copied', repaint: 'repainted', neighbour: 'filled from a neighbour', old_roll: 'an old roll', archived: 'archived' }[to.source] || to.source || '?';
      const here = String(i.name || '').split(' / ').slice(1).join(' / ') || String(i.name || '');
      const fl = i.flags || {};
      const deltas = [];
      if (Array.isArray(fl.raised) && fl.raised.length) deltas.push(`raises ${fl.raised.join(', ')}`);
      if (Array.isArray(fl.cleared) && fl.cleared.length) deltas.push(`clears ${fl.cleared.join(', ')}`);
      return { line: `${here} <- ${to.name || to.label || '?'} (${src}${i.why === 'pinned' ? '; a pinned choice re-applied' : ''})`, deltas: deltas.join('; ') || 'no flag changes', why: i.why, from: i.from || null, to: i.to || null, name: i.name, slot: i.slot, group: i.group };
    });
  }
  function batchSummary(b) {
    const items = b && Array.isArray(b.items) ? b.items : [];
    const staged = items.filter((i) => i.why === 'staged').length, pinned = items.filter((i) => i.why === 'pinned').length;
    const parts = [`Export replaces ${items.length} frame${items.length === 1 ? '' : 's'} of ${b && b.code ? b.code : 'this look'}'s installed strip`];
    if (pinned) parts.push(`${staged} staged, ${pinned} pinned choice${pinned === 1 ? '' : 's'} re-applied`);
    parts.push(b && b.in_play ? 'the game PLAYS this look' : 'the game does not play this look');
    parts.push(`the old strip is kept under ${b && b.backup_dir ? b.backup_dir : 'tools/level_editor/backups/'}/ and a failed merge or import puts it back`);
    return parts.join(' · ');
  }

  /** A group's name on a tab: "run · side". */
  function groupLabel(g) { return `${ANIM_LABEL[g.base] || g.base} · ${VIEW_LABEL[g.view] || g.view}`; }

  /** The selection after a click on slot i: a plain click selects it alone (or clears it when it was the only one),
   *  ctrl toggles it, shift selects the range from the anchor (the last plain click). Returns {set, anchor}. */
  function select(set, i, opts, anchor) {
    const o = opts || {};
    const cur = new Set(Array.isArray(set) ? set : Array.from(set || []));
    if (o.shift && isInt(anchor)) {
      const a = Math.min(anchor, i), b = Math.max(anchor, i);
      const out = new Set(o.ctrl ? cur : []);
      for (let k = a; k <= b; k++) out.add(k);
      return { set: out, anchor };
    }
    if (o.ctrl) {
      if (cur.has(i)) cur.delete(i); else cur.add(i);
      return { set: cur, anchor: i };
    }
    if (cur.size === 1 && cur.has(i)) return { set: new Set(), anchor: i };
    return { set: new Set([i]), anchor: i };
  }

  /** The slots as text: "3-5, 9". */
  function slotsText(set) {
    const list = Array.from(set || []).filter(isInt).sort((a, b) => a - b);
    const out = [];
    let i = 0;
    while (i < list.length) {
      let j = i;
      while (j + 1 < list.length && list[j + 1] === list[j] + 1) j++;
      out.push(j > i + 1 ? `${list[i]}-${list[j]}` : (j === i + 1 ? `${list[i]}, ${list[j]}` : String(list[i])));
      i = j + 1;
    }
    return out.join(', ');
  }

  /** A frame list from typed text ("3-5, 9" or "3 4 5"), kept to 0..n-1, sorted, unique; {list, error}. */
  function parseSlots(text, n) {
    const t = String(text == null ? '' : text).trim();
    if (!t) return { list: [], error: '' };
    const out = new Set();
    for (const part of t.split(/[\s,;]+/).filter(Boolean)) {
      const m = /^(\d+)-(\d+)$/.exec(part);
      if (m) { for (let k = Number(m[1]); k <= Number(m[2]); k++) out.add(k); continue; }
      if (!/^\d+$/.test(part)) return { list: [], error: `${JSON.stringify(part)} is not a frame number` };
      out.add(Number(part));
    }
    const list = Array.from(out).filter((k) => k >= 0 && k < n).sort((a, b) => a - b);
    return { list, error: list.length ? '' : `no frame in 0..${n - 1}` };
  }

  /** What the preview plays: the effective frame of every slot, in order: [{slot, url, how, staged}]. */
  function playlist(detail) {
    const slots = detail && Array.isArray(detail.slots) ? detail.slots : [];
    return slots.map((s) => ({ slot: s.slot, url: s.url || '', how: s.effective_how || '', staged: !!s.staged }));
  }

  /** The preview rate of an animation as the game plays it (StripPlayer's rule): run fps.run (a creature 10, a hero
   *  14), die fps.die (6 / 8), hit 8 / 12, idle 6, attack 8, cheer 6. */
  function previewFps(kind, base, fps) {
    const f = fps || {};
    const hero = kind === 'hero';
    if (base === 'run') return Number(f.run) > 0 ? Number(f.run) : (hero ? 14 : 10);
    if (base === 'die') return Number(f.die) > 0 ? Number(f.die) : (hero ? 8 : 6);
    if (base === 'hit') return Number(f.hit) > 0 ? Number(f.hit) : (hero ? 12 : 8);
    if (base === 'attack') return 8;
    return 6;
  }

  /** The repair window as tools/vace_repair.window_plan builds it: {mode, frames, redone, note}. */
  function repairPlan(n, loop, slots, mode) {
    let m = mode || 'auto';
    if (m === 'auto') m = (loop && n <= 12) ? 'double' : 'single';
    let frames;
    if (loop && m === 'double') frames = 2 * n + 1;
    else if (loop) frames = n + 1;
    else frames = n;
    while ((frames - 1) % 4) frames++;
    const redo = Array.from(slots || []).filter((k) => isInt(k) && k >= 0 && k < n);
    let note = '';
    if (n < 2) note = 'one frame: there is no stretch to pin it between; repaint it instead';
    else if (!redo.length) note = 'no frames chosen';
    else if (redo.length >= n) note = 'every frame: that is a new clip, re-roll the look instead';
    else if (loop && m === 'double') note = `the whole ${ANIM_LABEL.run === 'run' ? 'loop' : 'loop'} goes in twice plus its first frame (${frames} frames); the ${redo.length} chosen are masked in both passes and taken from the second`;
    else if (loop) note = `the loop goes in once plus its first frame (${frames} frames)`;
    else note = `the animation goes in as it is${frames > n ? `, its last frame held to ${frames}` : ''}`;
    return { mode: m, frames, redone: redo, note, ok: n >= 2 && redo.length > 0 && redo.length < n };
  }

  /** The badges of a slot record (the group detail's) with its flags: [{key, text, title, cls}]. */
  function badges(s, flags) {
    const out = [];
    if (s.staged) out.push({ key: 'staged', text: 'staged', cls: 'staged', title: `this choice is not exported yet (${s.staged.slice(0, 8)}): Export writes it into the strip` });
    if (s.pinned) out.push({ key: 'pinned', text: 'pinned', cls: 'pinned', title: 'a human chose this frame: a re-roll never replaces it' });
    if (s.installed_differs) out.push({ key: 'differs', text: 'strip differs', cls: 'differs', title: 'the installed strip holds another frame than the pinned choice: Export puts the choice in' });
    const f = flags || {};
    for (const k of ['empty', 'jump', 'footprint', 'seam', 'silhouette']) {
      if (f[k]) out.push({ key: k, text: k, cls: 'flag', title: f[k].rule || k });
    }
    return out;
  }

  /** A version in words: "SP-B / Run / Side / Frame 02 / v2 · painted anew by VACE · seed 24110 · walked on spider_walk · 13:20"
   *  (pass 96: Garry's label first; the short `label` when the record carries no name). */
  function versionText(v) {
    const bits = [v.name || v.label || v.id];
    bits.push(SOURCE_TEXT[v.source] || v.source || '?');
    if (v.from && v.from.label) bits.push(`from ${v.from.label}${v.from.code ? ' of ' + v.from.code : ''}${v.from.removed ? ' (removed look)' : ''}`);
    if (v.seed != null && v.source === 'vace') bits.push(`seed ${v.seed}`);
    if (v.driver && v.driver.name) bits.push(`walked on ${v.driver.name}${v.driver.ctl_sig ? ' (' + String(v.driver.ctl_sig).slice(0, 8) + ')' : ''}`);
    if (v.shrunk) bits.push(`shrunk to ${Math.round(Number(v.shrunk) * 100)}% to fit the cell`);
    if (v.time) bits.push(String(v.time).replace('T', ' ').slice(5, 16));
    return bits.join(' · ');
  }

  /** The confirm box before exporting the look the game plays (pass 95 resume, AN-09 Q5's default), or '' when none is needed. */
  function exportConfirmText(code, total, inPlay, id) {
    if (!inPlay) return '';
    return `${code} is the look the game plays for ${id || 'this asset'}. Export replaces the strip it shows with ${total} changed frame${total === 1 ? '' : 's'} (the old strip is kept under tools/level_editor/backups/${id || '<id>'}/, and a failed merge or import puts it back). Export now?`;
  }

  /** Where the frames live, in words (the help line under the view). */
  function whereLine(d) {
    const parts = [];
    if (d.strip_file) parts.push(`the game plays the strip ${d.strip_file}`);
    parts.push(d.clip_dir ? `the video model's frames are in ${d.clip_dir}/ (out_NN kept, full_NN all)` : 'no clip cache for this animation (procedural, or painted before the cache was kept)');
    if (d.path) parts.push(`every version of every frame is in ${d.path}/slot_NN/`);
    if (d.backups_dir) parts.push(`the old strip of every export in ${d.backups_dir}/ (the newest 30 kept)`);
    return parts.join('; ');
  }

  /** Newest first, the installed one last. */
  function versionsNewestFirst(list) {
    return (Array.isArray(list) ? list.slice() : []).sort((a, b) => (Number(b.n) || 0) - (Number(a.n) || 0));
  }

  /** The warnings of another look's frames for this one (frame_px, slot count, the driver). */
  function compat(other, n, framePx, driver) {
    const out = [];
    if (Number(other.frame_px) !== Number(framePx)) out.push(`its cells are ${other.frame_px} px, this look's ${framePx}: a copied cell is resized`);
    if (Number(other.n) !== Number(n)) out.push(`it has ${other.n} frames in this animation, this look ${n}: slot numbers do not line up`);
    if (other.driver && driver && other.driver !== driver) out.push(`walked on another driver (${other.driver}): the poses may differ`);
    return out;
  }

  /** The dialog's one-line summary: "13 animations · 95 frames · 3 staged". */
  function summaryLine(sum) {
    const gs = sum && Array.isArray(sum.groups) ? sum.groups : [];
    const frames = gs.reduce((a, g) => a + (Number(g.n) || 0), 0);
    const staged = gs.reduce((a, g) => a + (Number(g.staged) || 0), 0);
    return `${gs.length} animation${gs.length === 1 ? '' : 's'} · ${frames} frames · ${staged} staged`;
  }

  function step(pos, n, d, loop) {
    if (n <= 0) return 0;
    const q = pos + d;
    if (loop) return ((q % n) + n) % n;
    return Math.max(0, Math.min(n - 1, q));
  }

  const api = { VIEWS, VIEW_LABEL, ANIM_LABEL, SPEEDS, ZOOMS, SOURCE_TEXT, groupLabel, select, slotsText, parseSlots, playlist, previewFps, repairPlan, badges, versionText, versionsNewestFirst, compat, summaryLine, step, exportConfirmText, whereLine,
    VIEW_WORD, SOURCE_OPTIONS, TIME_OPTIONS, frameLabel, nameOf, sourceMark, filterVersions, batchLines, batchSummary };   // pass 96
  return api;
})();
if (typeof module !== 'undefined') module.exports = FramesModel;
