// Pass 110 (lane BOSS): the Timeline's "Boss fights" section. Garry (2026-10-28): "Currently I don't quite understand
// which enemies are going to be spawning during the Boss fight ... I'd like some control over which enemies spawn during
// the Boss fight. Just add a 2 minute window in the Timeline where I can set up the cycle of enemies that will be
// spawning. Basically I will be able to set them up as I always do with the knowledge that as long as the Boss Fight is
// continuing it will be those enemies at that pace that will be spawning."
//
// One panel per stage in view (the All tab: every stage; a stage tab: its own): the stage's boss, the window's switch,
// its cycle length and its Max count (bodies), + Row (continuous / waves / once), and its rows as bars on the fight's own
// clock (0:00 = the boss arrives, the cycle's end where it loops), with the presence fill and the yellow etches the Rows
// lane draws. A bar is dragged to move it, its ends to set its start and its until (whole seconds, 5 s with Snap on, Alt
// for a free drag); a click opens it in the inspector with the roster row's own form (inspector.js bossEnv). Under the
// rows, the window's cycle estimate: alive over two cycles against Max count (model.js bossFightCycle). The window lives
// in timeline_data.stage_list[s].boss_fight {enabled, length, max_count, roster}; the game's rule is
// game/core/systems/BossFightWindow.gd (docs/waves_schema.md "Pass 110", docs/level_editor.md "Pass 110").
'use strict';

const BossFights = (() => {
  const { el, svg, fmtT, fmtN, clear } = U;
  const LEFT = 220;         // the label column inside the panel's drawing (icon and name)
  const PAD_R = 18;
  const AXIS_H = 24, ROW_H = 30, SPARK_H = 54;
  const HANDLE = 7;
  const SNAP_S = 5;         // seconds a drag snaps to with Snap on
  let drag = null;          // {s, i, mode, x0, t0, until0, w0, before, moved, spp}
  let lastHost = null;

  /** The stages whose panels show: every stage on All, the open one on a stage tab. */
  function stagesInView() {
    const vs = App.viewStage();
    const L = App.stageList();
    return vs == null ? L : L.filter((w) => w.i === vs);
  }

  /** The boss of stage s (its stage_list entry's, else its boss event's). */
  function bossOf(s) { return typeof StageModel !== 'undefined' ? StageModel.bossOf(App.tl(), s) : App.stageWindow(s).boss; }

  /** The collapsed section's line: each stage's window in a few words. */
  function summary() {
    return App.stageList().map((w) => {
      const b = Model.bossFight(App.tl(), w.i);
      if (!b) return `${w.name}: no window`;
      return `${w.name}: ${Model.bossFightRows(b).length} rows, max ${Model.bossFightMax(b) < 0 ? 'none' : Model.bossFightMax(b)}${b.enabled === false ? ' (off)' : ''}`;
    }).join(' · ');
  }

  // ------------------------------------------------------------------ drawing

  function render(host) {
    lastHost = host;
    clear(host);
    host.appendChild(el('div', { class: 'bf-intro muted small' },
      el('b', { text: 'What spawns while the boss lives. ' }),
      'A stage with a window: from its boss\'s arrival until it dies only the window\'s rows spawn, as a cycle on the fight\'s own clock (0:00 = the boss arrives) that starts again every cycle, kept under the window\'s Max count (bodies alive: the boss, its summons and the stage\'s leftovers count too). The boss\'s own summons still come. A stage without one plays its fight as before: the stage\'s rows still open at its end, into boss_cap_frac of the cap. Drag a bar or its ends; click it to edit it with the usual row form. The line under the rows is the window\'s own estimate (alive over two cycles); the run charts above (On screen, Spawned so far) still draw a boss fight without its window.'));
    for (const w of stagesInView()) host.appendChild(panel(w));
  }

  /** The width the panel's drawing gets (the strip's, which stays in view while the lanes scroll sideways). */
  function drawWidth(host) {
    const sb = host && host.closest ? host.closest('.tl-scroll') : null;
    const vis = sb ? sb.clientWidth : 0;
    const w = (host && host.clientWidth) || vis || 1000;
    return Math.max(520, Math.min(w, vis || w) - 30);
  }

  function panel(w) {
    const s = w.i;
    const tl = App.tl();
    const b = Model.bossFight(tl, s);
    const bossId = bossOf(s);
    const selKey = App.selKey();
    const iss = App.issuesFor(`bossfight:${s}`);
    const box = el('div', { class: 'bf-panel' + (b ? '' : ' none') + (b && b.enabled === false ? ' off' : '') + (selKey === `bossfight:${s}` ? ' selected' : '') + (iss ? ' has-' + iss.level : ''), 'data-bf-stage': String(s) });
    // the head: the stage and its boss (a click opens the window's card), the switch, the numbers, + Row, Remove
    const name = el('button', { class: 'bf-name', type: 'button', title: 'open this window\'s card in the inspector (what it does, its rows, its cycle estimate)', onclick: () => App.select({ kind: 'bossfight', s }) },
      el('b', { text: `Stage ${s + 1} · ${w.name}` }),
      bossId && App.creature(bossId) ? el('img', { src: App.iconFor(bossId), width: 20, height: 20, alt: '' }) : null,
      el('span', { text: bossId ? `vs ${App.creatureName(bossId)}` : 'no boss' }),
      iss ? el('span', { class: 'bf-iss ' + iss.level, title: iss.msgs.join('\n'), text: '!' }) : null);
    const head = el('div', { class: 'bf-head' }, name);
    if (!b) {
      const frac = tl.boss_cap_frac == null ? 0.3 : Number(tl.boss_cap_frac);
      const cap = Math.floor(App.capAt(Math.max(w.end - 1e-3, 0)) * frac);
      head.appendChild(el('span', { class: 'muted small bf-today', text: `No window: this fight spawns the stage's rows still open at ${fmtT(w.end)}, into ${frac} of the cap (≈${cap} load), for as long as the boss lives.` }));
      head.appendChild(el('button', { class: 'btn small', type: 'button', text: 'Add a boss fight window', title: 'a 2:00 cycle with Max count 40 and no rows yet: from then on only its rows spawn while this stage\'s boss lives', onclick: () => App.addBossFight(s) }));
      box.appendChild(head);
      return box;
    }
    const len = Model.bossFightLen(b);
    const on = el('input', { type: 'checkbox', title: 'off keeps the window and its rows but plays the fight as before (for comparing)' });
    on.checked = b.enabled !== false;
    on.addEventListener('change', () => App.setBossFight(s, 'enabled', on.checked ? null : false));
    head.appendChild(el('label', { class: 'bf-ctl', title: on.title }, on, 'On'));
    head.appendChild(numBox(s, b, 'length', 'Cycle', 's', 'seconds of one cycle: the rows\' times run from 0:00 to this, then the cycle starts again (empty: 120)', Model.BOSS_FIGHT_DEF.length, 1, false));
    head.appendChild(numBox(s, b, 'max_count', 'Max count', '', 'the most creatures alive during the fight, counted as bodies: the boss, its summons and what is left of the stage\'s crowd count too; -1 = no limit but the hard cap (empty: 40)', Model.BOSS_FIGHT_DEF.max_count, -1, true));
    const adds = el('span', { class: 'bf-adds' }, el('span', { class: 'muted small', text: '+ Row' }));
    for (const [k, label, help] of [['continuous', 'continuous', 'drawn by its weight at every spawn check, keeping the fight topped up to Max count'], ['waves', 'waves', 'a wave every 30 s (Every), 6 a wave (Per wave)'], ['once', 'once', 'one wave a cycle, 8 in a ring']]) {
      adds.appendChild(el('button', { class: 'btn small', type: 'button', text: label, title: `add a ${label} row at 0:00 of the cycle: ${help}`, onclick: () => App.newBossRow(s, k, 0) }));
    }
    head.appendChild(adds);
    head.appendChild(el('span', { class: 'spacer' }));
    head.appendChild(el('button', { class: 'btn small danger', type: 'button', text: 'Remove window', title: 'delete this window and its rows: the fight plays as before (Ctrl+Z undoes)', onclick: () => { if (confirm(`Remove stage ${s + 1}'s boss fight window and its ${Model.bossFightRows(b).length} rows? The fight then plays as before (Ctrl+Z undoes).`)) App.removeBossFight(s); } }));
    box.appendChild(head);
    if (b.enabled === false) box.appendChild(el('div', { class: 'bf-offnote small', text: 'Off: the fight plays as before (the stage\'s rows still open at its end, boss_cap_frac of the cap); the rows below are kept for later.' }));
    box.appendChild(drawRows(s, b, len, drawWidth(lastHost)));
    box.appendChild(drawSpark(s, b, len, drawWidth(lastHost)));
    return box;
  }

  /** A number box of the window's head (length, max_count); empty = the game's default. */
  function numBox(s, b, k, label, unit, help, def, min, intOnly) {
    const inp = el('input', { type: 'number', class: 'num tiny', step: intOnly ? 1 : 'any', min, value: b[k] == null ? '' : b[k], placeholder: String(def), title: help, 'data-bf': k });
    inp.addEventListener('change', () => {
      const v = U.parseNum(inp.value);
      App.setBossFight(s, k, v == null ? null : (intOnly ? Math.round(v) : v));
    });
    inp.addEventListener('keydown', (e) => { e.stopPropagation(); if (e.key === 'Enter') inp.blur(); });
    return el('label', { class: 'bf-ctl', title: help }, label, inp, unit ? el('span', { class: 'muted small', text: unit }) : null);
  }

  function textWidth(str, px) { return String(str).length * px * 0.56; }
  /** A chip on a bar (the Rows lane's look): its text in a rounded box; returns the x after it. */
  function chip(parent, tx, ty, text, cls, title) {
    const wdt = textWidth(text, 10) + 10;
    const g = svg('g', { class: 'chip ' + (cls || '') }, svg('rect', { x: tx, y: ty, width: wdt, height: 14, rx: 3 }), svg('text', { x: tx + 5, y: ty + 10.5, class: 'chip-text', text }));
    if (title) g.appendChild(svg('title', {}, title));
    parent.appendChild(g);
    return tx + wdt + 4;
  }

  function drawRows(s, b, len, W) {
    const rows = Model.bossFightRows(b);
    const n = Math.max(rows.length, 1);
    const H = AXIS_H + n * ROW_H + 6;
    const span = W - LEFT - PAD_R;
    const x = (t) => LEFT + (Math.max(0, Math.min(len, t)) / len) * span;
    const s0 = svg('svg', { class: 'bf-svg', width: W, height: H, viewBox: `0 0 ${W} ${H}` });
    // the axis: a tick every 10 s, a label every 30 (every 60 on a long cycle), the loop at the end
    const step = len > 240 ? 60 : 30;
    for (let t = 0; t <= len + 1e-9; t += 10) {
      const big = Math.abs(t % step) < 1e-9;
      s0.appendChild(svg('line', { x1: x(t), x2: x(t), y1: AXIS_H - (big ? 8 : 4), y2: H, class: big ? 'bf-grid big' : 'bf-grid' }));
      // the cycle's end has the loop's own label
      if (big && t < len - 1e-9 && x(len) - x(t) > 60) s0.appendChild(svg('text', { x: x(t) + 3, y: 11, class: 'tick-text', text: fmtT(t) }));
    }
    s0.appendChild(svg('line', { x1: x(len), x2: x(len), y1: 0, y2: H, class: 'bf-loop' }));
    s0.appendChild(svg('text', { x: Math.max(LEFT + 4, x(len) - 4), y: 11, 'text-anchor': 'end', class: 'bf-loop-text', text: `↻ ${fmtT(len)}: the cycle starts again` }));
    s0.appendChild(svg('text', { x: 6, y: 11, class: 'tick-text', text: 'fight clock (0:00 = the boss arrives)' }));
    if (!rows.length) s0.appendChild(svg('text', { x: LEFT + 6, y: AXIS_H + 19, class: 'hint-text', text: 'no rows: nothing spawns in the fight but the boss\'s own summons ("+ Row" adds one)' }));
    // one presence scale for the window
    let maxW = 1;
    for (const r of rows) if (U.isObj(r)) { if (Array.isArray(r.weights) && r.weights.length) for (const p of r.weights) maxW = Math.max(maxW, Number(p[1]) || 0); else maxW = Math.max(maxW, App.rowWeight(r, Number(r.t) || 0)); }
    const tl = App.tl();
    const si = tl.spawn_interval == null ? 0.5 : Number(tl.spawn_interval);
    const lateT = tl.weight_late_t;
    const selKey = App.selKey();
    rows.forEach((r, i) => {
      if (!U.isObj(r)) return;
      const key = `bossrow:${s}:${i}`;
      const y0 = AXIS_H + i * ROW_H + 3, bh = ROW_H - 6;
      const t = Math.max(0, Number(r.t) || 0);
      const tEnd = Math.max(t, Model.bossRowEnd(b, r));
      const x0 = x(t), x1 = Math.max(x0 + 6, x(tEnd));
      const fid = Timeline.firstEnemy(r);
      const c = App.creature(fid);
      const role = TimelineModel.roleOf(r);
      const col = TimelineModel.roleColor(role);
      const pace = TimelineModel.paceOf(r);
      const iss = App.issuesFor(key);
      // the label column: icon and name (a click opens the row)
      const lab = svg('g', { class: 'bf-label' + (selKey === key ? ' selected' : ''), 'data-key': key });
      lab.appendChild(svg('rect', { x: 0, y: y0, width: LEFT - 8, height: bh, rx: 4, class: 'bf-label-bg' }));
      lab.appendChild(svg('rect', { x: 0, y: y0, width: 3, height: bh, fill: col }));
      if (fid && c) lab.appendChild(svg('image', { href: App.iconFor(fid, r.variant), x: 7, y: y0 + 2, width: 20, height: 20, preserveAspectRatio: 'xMidYMid meet' }));
      const nm = `${r.name ? r.name + ': ' : ''}${Timeline.enemyWords(r)}`;
      lab.appendChild(svg('text', { x: 32, y: y0 + 15, class: 'bar-text', text: nm.length > 26 ? nm.slice(0, 25) + '…' : nm }, svg('title', {}, `${nm}${r.id ? ` (${r.id})` : ''}: click to edit`)));
      lab.addEventListener('pointerdown', (e) => { if (e.button !== 0) return; e.stopPropagation(); App.select({ kind: 'bossrow', s, i }); });
      s0.appendChild(lab);
      const g = svg('g', { class: 'bar bf-bar pace-' + pace + (role ? ' role-' + role : ' untagged') + (selKey === key ? ' selected' : '') + (iss ? ' has-' + iss.level : ''), 'data-key': key });
      g.appendChild(svg('rect', { x: x0, y: y0, width: x1 - x0, height: bh, rx: 4, class: 'bar-body', style: `stroke:${col}` }));
      // the presence fill (its keyframes on the fight clock)
      const yb = y0 + bh - 3, ysp = bh - 6;
      const yW = (v) => yb - (Math.max(0, v) / maxW) * ysp;
      const ws = Array.isArray(r.weights) ? r.weights.filter((p) => Array.isArray(p)).map((p) => [Number(p[0]) || 0, Number(p[1]) || 0]).sort((a, c2) => a[0] - c2[0]) : [];
      const verts = [[x0, yW(App.rowWeight(r, t))]];
      for (const p of ws) if (p[0] > t && p[0] < tEnd) verts.push([x(p[0]), yW(p[1])]);
      verts.push([x1, yW(App.rowWeight(r, tEnd))]);
      g.appendChild(svg('path', { d: `M${x0},${yb} ${verts.map(([vx, vy]) => `L${vx},${vy}`).join(' ')} L${x1},${yb} Z`, class: 'w-area', fill: col }));
      g.appendChild(svg('polyline', { points: verts.map(([vx, vy]) => `${vx},${vy}`).join(' '), class: 'w-edge', stroke: col }));
      // what it brings, as on the Rows lane
      let tx = x0 + 6;
      tx = chip(g, tx, y0 + 2, TimelineModel.quantityText(r, Model.rowWaveCount(r, c), null), 'chip-qty' + (pace !== 'continuous' ? ' paced' : ''), pace === 'continuous' ? 'continuous: drawn at every spawn check into the room under Max count' : pace === 'once' ? 'one wave a cycle' : 'paced as waves');
      if (r.elite != null && r.elite !== '') tx = chip(g, tx, y0 + 2, `★ ${r.elite === 'random' ? 'elite' : r.elite}`, 'chip-elite');
      if (r.special === true) tx = chip(g, tx, y0 + 2, '◆ special', 'chip-special');
      if (r.respect_cap === false && pace !== 'continuous') tx = chip(g, tx, y0 + 2, 'no cap', 'chip-nocap', 'on top of Max count (the hard cap still holds)');
      if (r.variant) tx = chip(g, tx, y0 + 2, r.variant, 'chip-variant');
      if (r.pattern && r.pattern !== 'pack') tx = chip(g, tx, y0 + 2, r.pattern === 'in_front' ? 'In front' : r.pattern, 'chip-pattern');
      if (r.stats && Object.keys(r.stats).length) chip(g, tx, y0 + 2, 'overrides', 'chip-wrench');
      // the yellow etches: each wave that comes; a tick at each draw of a drawn row
      const et = svg('g', { class: 'etches' + (Model.rowPaced(r) ? ' paced' : '') });
      const spp = len / Math.max(span, 1);
      if (Model.rowDrawn(r)) {
        const dense = Model.rowDrawInterval(r, si) < Model.ETCH_MIN_PX * spp;
        for (const [a, c2] of Model.presenceSpans(r, t, tEnd, lateT)) {
          if (dense) { et.appendChild(svg('line', { x1: x(a), x2: x(c2), y1: y0 + bh - 2.5, y2: y0 + bh - 2.5, class: 'etch-dots' })); continue; }
          let d = '';
          for (const tk of Model.rowDrawTimes(r, a, Math.min(c2, tEnd - 1e-6), si, lateT)) d += `M${x(tk).toFixed(1)},${y0 + bh}v-5`;
          if (d) et.appendChild(svg('path', { d, class: 'etch-draw' }));
        }
      }
      if (Model.rowPaced(r)) {
        for (const tk of Model.thinTimes(Model.rowEtchTimes(r, tEnd - 1e-6, lateT), Model.ETCH_MIN_PX * spp).times) {
          if (tk < t - 1e-9 || tk >= tEnd) continue;
          et.appendChild(svg('line', { x1: x(tk), x2: x(tk), y1: y0 + bh - 1, y2: y0 + bh - 11, class: 'etch-tick' + (pace === 'once' ? ' once' : '') }));
        }
      }
      g.appendChild(et);
      const left = svg('rect', { x: x0, y: y0, width: HANDLE, height: bh, class: 'handle' }, svg('title', {}, 'drag to move the start'));
      const right = svg('rect', { x: x1 - HANDLE, y: y0, width: HANDLE, height: bh, class: 'handle' }, svg('title', {}, r.until == null || r.until === '' ? 'drag to give the row an end before the cycle\'s' : 'drag to move the end (to the cycle\'s end: no end)'));
      left.addEventListener('pointerdown', (e) => startDrag(e, s, i, 'start', span, len));
      right.addEventListener('pointerdown', (e) => startDrag(e, s, i, 'until', span, len));
      g.addEventListener('pointerdown', (e) => startDrag(e, s, i, 'move', span, len));
      g.appendChild(left);
      g.appendChild(right);
      g.appendChild(svg('title', {}, `${nm}: ${fmtT(t)} → ${fmtT(tEnd)} of the cycle · ${TimelineModel.quantityText(r, Model.rowWaveCount(r, c), null)}${iss ? '\n' + iss.msgs.join('\n') : ''}\ndrag to move, drag an end to change it, click to edit`));
      if (iss) {
        g.appendChild(svg('g', { class: 'issue ' + iss.level }, svg('circle', { cx: x0 + 1, cy: y0 + 1, r: 7 }), svg('text', { x: x0 + 1, y: y0 + 4.6, 'text-anchor': 'middle', class: 'issue-mark', text: '!' })));
      }
      s0.appendChild(g);
    });
    if (drag && drag.s === s && drag.tag) s0.appendChild(svg('text', { x: Math.min(W - 120, Math.max(LEFT, drag.tagX)), y: H - 2, class: 'bf-dragtag', text: drag.tag }));
    return s0;
  }

  /** The window's cycle estimate under its rows: alive (the boss in) over two cycles against Max count (dashed). */
  function drawSpark(s, b, len, W) {
    const cy = cycleOf(s);
    const wrap = el('div', { class: 'bf-spark' });
    if (!cy) return wrap;
    const span = W - LEFT - PAD_R;
    const n = cy.alive.length;
    const top = Math.max(cy.peak, cy.max > 0 ? cy.max : 0, 5) * 1.12;
    const s0 = svg('svg', { class: 'bf-spark-svg', width: W, height: SPARK_H, viewBox: `0 0 ${W} ${SPARK_H}` });
    const x = (k) => LEFT + (k / Math.max(n - 1, 1)) * span;
    const y = (v) => SPARK_H - 6 - (v / top) * (SPARK_H - 14);
    s0.appendChild(svg('line', { x1: x((n - 1) / 2), x2: x((n - 1) / 2), y1: 4, y2: SPARK_H - 4, class: 'bf-loop' }));
    if (cy.max >= 0) s0.appendChild(svg('line', { x1: LEFT, x2: LEFT + span, y1: y(cy.max), y2: y(cy.max), class: 'bf-max' }, svg('title', {}, `Max count ${cy.max}`)));
    s0.appendChild(svg('polyline', { points: cy.alive.map((v, k) => `${x(k).toFixed(1)},${y(v).toFixed(1)}`).join(' '), class: 'bf-alive' }));
    s0.appendChild(svg('text', { x: 6, y: 14, class: 'tick-text', text: 'estimate: alive over two cycles' }));
    s0.appendChild(svg('text', { x: 6, y: 28, class: 'tick-text', text: `peak ≈${fmtN(cy.peak, 0)}${cy.max >= 0 ? ` · max ${cy.max}` : ''}` }));
    s0.appendChild(svg('text', { x: 6, y: 42, class: 'tick-text', text: `≈${fmtN(cy.spawned[cy.cycles - 1], 0)} spawned a cycle` }));
    s0.appendChild(svg('title', {}, `What the window brings, an estimate: the hero kills ${Math.round(cy.turnover * 100)}% of the crowd a second, the fight starts with only the boss alive (the stage's leftovers and the boss's summons are not in it). Dashed: Max count. The line in the middle: where the second cycle starts. The run charts above still model the fight without its window.`));
    wrap.appendChild(s0);
    return wrap;
  }

  /** Stage s's cycle estimate at the page's kill rate (the Estimate box's number, else your runs' single number, else
   *  the default), cached per map state. */
  let cache = { key: '', v: null };
  function cycleOf(s) {
    const a = App.S.assume || {};
    const tv = typeof a.turnover === 'number' ? a.turnover : (App.S.fit && typeof App.S.fit.turnover === 'number' ? App.S.fit.turnover : Model.EST_DEF.turnover);
    const tl = App.tl();
    const key = JSON.stringify([App.S.mapId, App.S.enemiesRev, s, tv, Model.bossFight(tl, s), tl.hard_cap, tl.spawn_interval, tl.burst_min, tl.burst_max, tl.weight_late_t]);
    if (cache.key === key) return cache.v;
    const v = Model.bossFightCycle(tl, s, App.S.byId, { turnover: tv, cycles: 2 });
    cache = { key, v };
    return v;
  }

  // ------------------------------------------------------------------ dragging (its own: the fight clock, not the run's)

  function startDrag(e, s, i, mode, span, len) {
    if (e.button !== 0) return;
    e.stopPropagation();
    e.preventDefault();
    const ae = document.activeElement;
    if (ae && /^(INPUT|SELECT|TEXTAREA)$/.test(ae.tagName) && typeof ae.blur === 'function') ae.blur();
    const r = App.bossRows(s)[i];
    if (!r) return;
    drag = {
      s, i, mode, x0: e.clientX, moved: false, before: App.snapshot(), spp: len / Math.max(span, 1), len,
      t0: Number(r.t) || 0, until0: r.until == null || r.until === '' ? null : Number(r.until),
      w0: Array.isArray(r.weights) ? r.weights.map((p) => (Array.isArray(p) ? [Number(p[0]) || 0, Number(p[1]) || 0] : p)) : null,
      tag: '', tagX: 0,
    };
    document.body.classList.add('dragging');
    window.addEventListener('pointermove', onMove);
    window.addEventListener('pointerup', onUp, { once: true });
    // pressed: selected at once, so the inspector follows the drag (the Rows lane's rule)
    if (App.selKey() !== `bossrow:${s}:${i}`) {
      App.S.sel = { kind: 'bossrow', s, i };
      try { Inspector.render(document.getElementById('inspector')); } catch (err) { console.error('the inspector could not be drawn for the drag', err); }
    }
  }

  /** A dragged time: whole seconds, or SNAP_S with the page's Snap on (Alt held: free). */
  function snapT(v, alt) {
    const on = typeof Timeline !== 'undefined' && Timeline.snapOn && !alt;
    return on ? Math.round(v / SNAP_S) * SNAP_S : Math.round(v);
  }

  function onMove(e) {
    if (!drag) return;
    const dx = e.clientX - drag.x0;
    if (!drag.moved && Math.abs(dx) < 3) return;
    drag.moved = true;
    const r = App.bossRows(drag.s)[drag.i];
    if (!r) return;
    const len = drag.len;
    const dt = dx * drag.spp;
    if (drag.mode === 'move') {
      const spanT = drag.until0 != null ? drag.until0 - drag.t0 : 0;
      const maxT = drag.until0 != null ? Math.max(0, len - spanT) : Math.max(0, Math.floor(len) - 1);
      const nt = Math.max(0, Math.min(maxT, snapT(drag.t0 + dt, e.altKey)));
      const moved = nt - drag.t0;
      r.t = nt;
      if (drag.until0 != null) r.until = Math.min(len, Math.max(nt + 1, drag.until0 + moved));
      // its presence keyframes travel with it (fight-clock times), never out of the cycle
      if (drag.w0) r.weights = drag.w0.map((p) => (Array.isArray(p) ? [Math.max(0, Math.min(len, p[0] + moved)), p[1]] : p));
      drag.tag = `from ${fmtT(nt)}`;
    } else if (drag.mode === 'start') {
      const hi = (drag.until0 != null ? drag.until0 : len) - 1;
      r.t = Math.max(0, Math.min(Math.max(hi, 0), snapT(drag.t0 + dt, e.altKey)));
      drag.tag = `from ${fmtT(r.t)}`;
    } else {
      const base = drag.until0 != null ? drag.until0 : len;
      const nu = Math.max((Number(r.t) || 0) + 1, Math.min(len, snapT(base + dt, e.altKey)));
      // dragged to the cycle's end: no end (the row runs to the end of every cycle)
      if (nu >= len) delete r.until; else r.until = nu;
      drag.tag = nu >= len ? 'until the cycle\'s end' : `until ${fmtT(nu)}`;
    }
    drag.tagX = e.clientX - (lastHost ? lastHost.getBoundingClientRect().left : 0);
    if (lastHost) render(lastHost);
    try { Inspector.live(); } catch (_) { /* the form follows at the drop */ }
  }

  function onUp() {
    window.removeEventListener('pointermove', onMove);
    document.body.classList.remove('dragging');
    if (!drag) return;
    const d = drag; drag = null;
    const sel = { kind: 'bossrow', s: d.s, i: d.i };
    if (d.moved) {
      const r = App.bossRows(d.s)[d.i];
      if (r && Array.isArray(r.weights)) App.sortPoints(r.weights);
      App.S.sel = sel;
      App.pushHistory(d.before);
      App.render('all');
    } else {
      App.select(sel);
    }
  }

  return { render, summary, stagesInView, LEFT, get dragging() { return !!drag; } };
})();
