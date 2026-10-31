// Pass 87 (lane STOOLS; Garry: "LevelEditor will have tabs in the Timeline for each Stage (more Stages can be added and it
// should be fairly simple to add (choosing the colouring should be possible too))"): the strip of stage tabs above the
// Timeline ("All | Stage 1 | Stage 2 | Stage 3 | + Stage") and a stage's settings card in the inspector (its name, length,
// boss, words for the Stages menu, the colour of its look and the hell ground). The edits themselves are page-free in
// stage_model.js (StageModel, Node-tested); this file only draws and asks. A stage tab shows its window on the Timeline
// (timeline.js: the axis from the window's start, the rows open in it, the portal's timer and Endless after its boss).
'use strict';

const StageTabs = (() => {
  const { el, fmtT, fmtN, clear } = U;
  /** A colour the Stages menu's swatch shows for "no tint". */
  const SAND = '#cfae84';
  const ACTORS_DEF = 0.35;
  /** Pass 105 (lane LOOK): the shares the game takes when the filter names none (StageLook STRUCTURES_DEFAULT,
   *  ITEMS_DEFAULT). */
  const STRUCTURES_DEF = 0.3;
  const ITEMS_DEF = 0;

  // ------------------------------------------------------------------ the strip

  /** Open a stage tab (null = All) with its settings card, the axis fitted to it. */
  function open(k) {
    App.setStageView(k == null ? 'all' : k);
    App.S.sel = k == null ? null : { kind: 'stage', i: k };
    if (typeof Timeline !== 'undefined' && Timeline.fit) Timeline.fit();
    App.render('inspector');
    // each tab's own Sim (the newest of its stage by default)
    if (typeof Timeline !== 'undefined' && Timeline.loadSimList) Timeline.loadSimList(false);
  }

  function swatchDot(e) {
    const f = StageModel.filterOf(e);
    if (!(f.strength > 0)) return el('span', { class: 'stg-dot none', title: 'no tint (daylight)' });
    return el('span', { class: 'stg-dot', style: `background:${mixHex(SAND, f.color, f.strength)}`, title: `${f.color} at ${Math.round(f.strength * 100)}%` });
  }

  function renderStrip(host) {
    if (!host) return;
    clear(host);
    const L = App.stageList();
    const vs = App.viewStage();
    const counts = StageModel.rowNumbers(App.tl().roster || [], L.map((w) => ({ start: w.start, end: w.end }))).counts;   // pass 116
    host.appendChild(el('span', { class: 'stg-label', text: 'Stages' }));
    host.appendChild(el('button', { class: 'stg-tab' + (vs == null ? ' active' : ''), type: 'button', title: 'the whole map: every stage\'s window on the one run clock (each stage is its own run: the estimate starts a fresh hero at each window)', onclick: () => open(null) }, el('b', { text: 'All' }), el('small', { text: fmtT(App.runEnd()) })));
    for (const w of L) {
      const iss = App.issuesFor(`stage:${w.i}`);
      host.appendChild(el('button', { class: 'stg-tab' + (vs === w.i ? ' active' : '') + (iss ? ' ' + iss.level : ''), type: 'button', title: `Stage ${w.i + 1}: ${w.name}, ${fmtT(w.start)}–${fmtT(w.end)} on the map, ${fmtT(w.length)} to its boss${iss ? '\n' + iss.msgs.join('\n') : ''}`, onclick: () => open(w.i) },
        swatchDot(w.entry), el('b', { text: `Stage ${w.i + 1}` }), el('span', { class: 'stg-count', title: 'pass 116: the spawn rows that start in this stage (each row number is in the Spawn rows gutter)', text: `${counts[w.i] || 0} rows` }), el('span', { class: 'stg-name', text: w.name !== `Stage ${w.i + 1}` ? w.name : '' }), el('small', { text: fmtT(w.length) }), iss ? el('span', { class: 'stg-iss', text: '!' }) : null));
    }
    host.appendChild(el('button', { class: 'stg-tab add', type: 'button', title: 'append a stage after the last one: its settings copied from the last, no rows yet, its boss at its end', onclick: () => addStage() }, el('b', { text: '+ Stage' })));
    if (!Model.hasStageList(App.tl())) host.appendChild(el('span', { class: 'stg-note', text: `no stage list in the file yet: ${L.length} stages of ${fmtT(App.stageLength())} (stage_length); the first stage edit writes one` }));
    else if (vs != null) host.appendChild(el('span', { class: 'stg-note', text: `stage ${vs + 1}'s window: ${fmtT(App.stageStart(vs))}–${fmtT(App.stageEnd(vs))} on the map clock · a fresh hero at its start · the portal's ${fmtT(App.portalSeconds())} and Endless after its boss` }));
  }

  // ------------------------------------------------------------------ add, delete, length

  function words(list, n) {
    const l = list || [];
    return l.length > n ? `${l.slice(0, n).join(', ')} and ${l.length - n} more` : l.join(', ');
  }

  function addStage() {
    const L = App.stageList();
    const last = L[L.length - 1];
    const boss = StageModel.bossOf(App.tl(), last.i);
    const msg = `Add stage ${L.length + 1} after stage ${L.length} (${last.name})?\n\nIt starts at ${fmtT(last.end)} on the map clock and lasts ${fmtT(last.length)} like the last one, with its settings (boss ${boss ? App.creatureName(boss) : 'none'} at its end, its colour and hell ground). No spawn rows yet: add them on its tab.${Model.hasStageList(App.tl()) ? '' : '\n\nThe map has no stage list yet: this writes one (the stages as they are now).'}`;
    if (!confirm(msg)) return;
    let res = null;
    App.apply((d) => { res = StageModel.addStage(d); });
    App.toast(`Added stage ${res.i + 1} (${fmtT(res.start)}–${fmtT(res.end)})`, { undo: true });
    open(res.i);
  }

  function deleteStage(i) {
    const L = App.stageList();
    if (L.length <= 1) { App.toast('A map keeps at least one stage'); return; }
    const w = L[i];
    const pv = StageModel.removePreview(App.tl(), i);
    const later = L.length - 1 - i;
    const msg = `Delete stage ${i + 1} (${w.name}, ${fmtT(w.start)}–${fmtT(w.end)})?\n\n` +
      (pv.cut.length ? `These go with it: ${words(pv.cut, 12)}.\n` : 'Nothing lies wholly inside it.\n') +
      (pv.ends.length ? `Shortened to its start: ${words(pv.ends, 8)}.\n` : '') +
      (later ? `${later === 1 ? 'The stage after it moves' : `The ${later} stages after it move`} back by ${fmtT(w.length)} with their rows, events and curve points.\n` : '') +
      'Its entries in the per-stage lists (stage multipliers, hell share, mutation offers, caps) go too. Undo brings it all back.';
    if (!confirm(msg)) return;
    let res = null;
    App.apply((d) => { res = StageModel.removeStage(d, i); });
    if (!res || !res.ok) { App.toast(res ? res.why : 'Not deleted'); return; }
    App.toast(`Deleted stage ${i + 1}${res.cut.length ? ` and ${res.cut.length} things in it` : ''}`, { undo: true });
    open(App.viewStage() == null ? null : Math.max(0, Math.min(i, App.stages() - 1)));
  }

  /** The length box's confirm: what moves in each mode, and the buttons. */
  function lengthConfirm(host, i, len) {
    clear(host);
    host.hidden = false;
    const w = App.stageWindow(i);
    if (!(len >= 1) || len === w.length) { host.hidden = true; return; }
    const keep = StageModel.lengthPreview(App.tl(), i, len, 'keep');
    const str = StageModel.lengthPreview(App.tl(), i, len, 'stretch');
    const d = len - w.length;
    const later = App.stages() - 1 - i;
    host.appendChild(el('div', { class: 'stg-conf-head', text: `Stage ${i + 1}: ${fmtT(w.length)} → ${fmtT(len)} (${d > 0 ? '+' : '−'}${fmtT(Math.abs(d))}). Its boss moves to ${fmtT(w.start + len)}.` }));
    if (later) host.appendChild(el('div', { class: 'stg-conf-line', text: `${later === 1 ? 'Stage ' + (i + 2) + ' moves' : `Stages ${i + 2}–${i + 1 + later} move`} ${d > 0 ? 'later' : 'earlier'} by ${fmtT(Math.abs(d))} with ${later === 1 ? 'its' : 'their'} rows, events and curve points.` }));
    const keepWords = d > 0
      ? `Keep its own times: what it has stays where it is; its rows that ran to its end run on to the new end.`
      : `Keep its own times: ${keep.cut.length || keep.ends.length ? `past the new end ${keep.cut.length ? `these go: ${words(keep.cut, 8)}` : ''}${keep.cut.length && keep.ends.length ? '; ' : ''}${keep.ends.length ? `these end at the new end: ${words(keep.ends, 8)}` : ''}` : 'nothing lies past the new end'}.`;
    host.appendChild(el('div', { class: 'stg-conf-line' + (d < 0 && keep.cut.length ? ' warn' : ''), text: keepWords }));
    host.appendChild(el('div', { class: 'stg-conf-line', text: `Stretch its own times ×${fmtN(len / w.length, 2)}: every row, event and curve point inside it moves in proportion (${str.moved} times move; nothing is cut; the rule of the pass 87 migration).` }));
    const doIt = (mode) => {
      let res = null;
      App.apply((dd) => { res = StageModel.setLength(dd, i, len, mode); });
      host.hidden = true;
      App.toast(`Stage ${i + 1} is ${fmtT(len)} long (${mode === 'stretch' ? 'stretched' : 'its times kept'}${res && res.cut.length ? `; ${res.cut.length} cut` : ''})`, { undo: true });
      if (typeof Timeline !== 'undefined' && Timeline.fit && App.viewStage() != null) Timeline.fit();
    };
    host.appendChild(el('div', { class: 'stg-conf-acts' },
      el('button', { class: 'btn small primary', type: 'button', text: 'Keep its times', onclick: () => doIt('keep') }),
      el('button', { class: 'btn small', type: 'button', text: `Stretch ×${fmtN(len / w.length, 2)}`, onclick: () => doIt('stretch') }),
      el('button', { class: 'btn small ghost', type: 'button', text: 'Cancel', onclick: () => { host.hidden = true; App.render('inspector'); } })));
  }

  // ------------------------------------------------------------------ the card

  /** a '#rrggbb' mixed toward `b` by f (0 = a). */
  function mixHex(a, b, f) {
    const pa = hexRgb(a), pb = hexRgb(b);
    const m = pa.map((v, k) => Math.round(v + (pb[k] - v) * f));
    return '#' + m.map((v) => v.toString(16).padStart(2, '0')).join('');
  }
  function hexRgb(h) {
    const s = /^#?([0-9a-f]{6})$/i.exec(String(h || ''));
    const n = s ? parseInt(s[1], 16) : 0;
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  }
  /** SLOOK's multiply: a colour times lerp(white, filter, strength) (the world; the creatures by strength × actors). */
  function multiplied(base, color, strength) {
    const b = hexRgb(base), c = hexRgb(color);
    const m = b.map((v, k) => Math.round(v * (1 + (c[k] / 255 - 1) * strength)));
    return '#' + m.map((v) => Math.max(0, Math.min(255, v)).toString(16).padStart(2, '0')).join('');
  }

  /** The live swatch: the map's ground, rock and wall colours and the stage's boss, in daylight (top) and in this stage's
   *  look (bottom: the world times the filter, the creature by its share of it); a red warning ring on both (lane SLOOK
   *  draws telegraphs over the filter, untinted). */
  function drawSwatch(canvas, f, actors, bossId) {
    const g = canvas.getContext('2d');
    const W = canvas.width, H = canvas.height, rowH = H / 2;
    const tl = App.tl();
    const wall = (tl.wall_colors && tl.wall_colors.near) || '#856b6e';
    const rock = tl.rock_color || '#785c5e';
    const blocks = [['sand', SAND], ['rock', rock], ['wall', wall], ['stone', (tl.wall_colors && tl.wall_colors.stone) || '#c59e7b']];
    g.clearRect(0, 0, W, H);
    const bw = (W - 70) / blocks.length;
    for (let row = 0; row < 2; row++) {
      const s = row === 0 ? 0 : f.strength;
      blocks.forEach(([, col], k) => { g.fillStyle = multiplied(col, f.color, s); g.fillRect(k * bw, row * rowH, bw, rowH); });
      g.fillStyle = multiplied(SAND, f.color, s);
      g.fillRect(W - 70, row * rowH, 70, rowH);
      // a red warning ring (telegraphs draw over the filter)
      g.strokeStyle = '#ff3b30'; g.lineWidth = 2.5;
      g.beginPath(); g.ellipse(bw * 1.5, row * rowH + rowH / 2, 16, 7, 0, 0, Math.PI * 2); g.stroke();
      g.fillStyle = 'rgba(0,0,0,0.55)'; g.font = '10px sans-serif';
      g.fillText(row === 0 ? 'daylight' : 'this stage', 4, row * rowH + 12);
    }
    const src = bossId ? App.iconFor(bossId) : '';
    if (!src) return;
    const img = new Image();
    img.onload = () => {
      for (let row = 0; row < 2; row++) {
        const s = row === 0 ? 0 : f.strength * actors;
        const off = document.createElement('canvas');
        off.width = 44; off.height = 44;
        const o = off.getContext('2d');
        o.drawImage(img, 0, 0, 44, 44);
        if (s > 0) {
          o.globalCompositeOperation = 'multiply';
          o.fillStyle = multiplied('#ffffff', f.color, s);
          o.fillRect(0, 0, 44, 44);
          o.globalCompositeOperation = 'destination-in';
          o.drawImage(img, 0, 0, 44, 44);
        }
        g.drawImage(off, W - 57, row * rowH + (rowH - 44) / 2);
      }
    };
    img.src = src;
  }

  function fieldRow(label, help, control, note) {
    return Forms.row({ label, help }, control, note ? { after: el('div', { class: 'muted small', text: note }) } : undefined);
  }

  /** Stage i's settings in the inspector. */
  function card(container, i) {
    const tl = App.tl();
    const w = App.stageWindow(i);
    const e = w.entry || {};
    const set = (key, v, what) => { App.apply((d) => { StageModel.setField(d, i, key, v); App.S.sel = { kind: 'stage', i }; }); if (what) App.toast(what, { undo: true, ms: 2500 }); };
    // the head
    const acts = el('div', { class: 'insp-actions' });
    if (App.viewStage() !== i) acts.appendChild(el('button', { class: 'btn small', type: 'button', text: 'Open its tab', title: 'show only this stage\'s window on the Timeline', onclick: () => open(i) }));
    acts.appendChild(el('button', { class: 'btn small danger', type: 'button', text: 'Delete stage', title: 'remove this stage and what lies in its window (asks first)', disabled: App.stages() <= 1, onclick: () => deleteStage(i) }));
    acts.appendChild(el('button', { class: 'btn small ghost', type: 'button', text: '✕', title: 'close (Esc)', onclick: () => App.select(null) }));
    const head = el('div', { class: 'insp-head' }, el('div', { class: 'insp-kind', text: `Stage ${i + 1}` }), el('div', { class: 'insp-title', text: w.name }), acts,
      el('div', { class: 'insp-sub', text: `${fmtT(w.start)}–${fmtT(w.end)} on the map clock · ${fmtT(w.length)} to its boss · stage multiplier ×${fmtN(App.stageMult(i), 2)}` }));
    container.appendChild(head);
    const m = App.issuesFor(`stage:${i}`);
    if (m) container.appendChild(el('div', { class: 'insp-issues ' + m.level }, m.msgs.map((x) => el('div', { text: x }))));
    container.appendChild(el('p', { class: 'insp-help', text: 'Each stage is its own run (pass 87): the player picks it in the Stages menu once the stage before is beaten; a fresh hero (level 1, his start weapon) starts at its window\'s start on the run clock, the run ends at its boss, then the portal opens with a timer and only EXTRACT; when the timer runs out, Endless starts. The words and the colour below are what the Stages menu and the game show.' }));
    if (!Model.hasStageList(tl)) container.appendChild(el('p', { class: 'insp-help warn', text: `This map has no stage list yet (its stages are ${App.stages()} × ${fmtT(App.stageLength())} from stage_length). The first edit here writes one.` }));
    const form = el('div', { class: 'form stg-form' });
    // the words
    form.appendChild(el('div', { class: 'fsection' }, el('h3', { text: 'The Stages menu' })));
    form.appendChild(fieldRow('Name', 'the stage\'s name on its card and in the Results ("Sundown", "Dusk", "Blood Moon")', Forms.textInput({ key: 'stage.name' }, e.name != null ? e.name : '', (v) => set('name', v), { placeholder: `Stage ${i + 1}`, path: 'stage.name' })));
    form.appendChild(fieldRow('Difficulty', 'one short line of what to expect ("Gentle: learn the creatures")', Forms.textInput({ key: 'stage.difficulty' }, e.difficulty || '', (v) => set('difficulty', v), { placeholder: 'Gentle: learn the creatures', path: 'stage.difficulty' })));
    form.appendChild(fieldRow('Description', 'a sentence or two under the picture', Forms.textareaInput({ key: 'stage.description' }, e.description || '', (v) => set('description', v), { rows: 3, placeholder: 'The canyon at dusk ...', path: 'stage.description' })));
    form.appendChild(fieldRow('Picture', 'the card\'s picture (lane SLOOK\'s capture tool writes art/ui/stages/<map>_s<k>.jpg in the stage\'s look); empty = that file', Forms.textInput({ key: 'stage.shot' }, e.shot || '', (v) => set('shot', v), { placeholder: `res://art/ui/stages/${App.S.mapId}_s${i + 1}.jpg`, path: 'stage.shot' })));
    // the window
    form.appendChild(el('div', { class: 'fsection' }, el('h3', { text: 'Its window' })));
    const conf = el('div', { class: 'stg-confirm', hidden: true });
    form.appendChild(fieldRow('Length', 'seconds from the stage\'s start to its boss (mm:ss works). Changing it moves the later stages and everything in them; you choose whether this stage\'s own rows keep their times or stretch with it', Forms.secondsInput({ key: 'stage.length', def: w.length }, w.length, (v) => lengthConfirm(conf, i, v), { path: 'stage.length' })));
    form.appendChild(conf);
    form.appendChild(fieldRow('Boss', 'the boss at the window\'s end (its boss event moves with the end; the stage run ends when it falls)', Forms.enemyPick(StageModel.bossOf(tl, i), (v) => { App.apply((d) => { StageModel.setBoss(d, i, v); App.S.sel = { kind: 'stage', i }; }); }, { prefer: 'boss', path: 'stage.boss', emptyLabel: 'no boss' })));
    // pass 107 (lane XPT): the stage's XP from kills (stage_list entry `xp_mult`, WaveTimeline.stage_xp_mult)
    form.appendChild(fieldRow('XP from kills', 'every kill\'s XP in this stage times this (`xp_mult`, 1 when unset; it holds through the boss, the portal and Endless). Each stage is a fresh level-1 run, so a stage whose creatures are rich in XP levels the hero much faster: lower it to slow the levels (0.5 = half the XP); empty = 1',
      Forms.numberInput({ key: 'stage.xp_mult', def: 1, min: 0, step: 0.05 }, e.xp_mult != null ? e.xp_mult : null, (v) => set('xp_mult', v, `Stage ${i + 1}'s XP from kills: x${v == null ? 1 : v}`), { path: 'stage.xp_mult', placeholder: 1 })));
    // the look
    form.appendChild(el('div', { class: 'fsection' }, el('h3', { text: 'Its look', title: 'lane SLOOK\'s filter: the world multiplied by the colour at this strength; the creatures and the hero by their share of it, so they stay brighter; telegraphs, gems and coins are drawn over it untinted' })));
    const f = StageModel.filterOf(e);
    const fe = U.isObj(e.filter) ? e.filter : {};
    let actors = fe.actors != null && isFinite(Number(fe.actors)) ? Number(fe.actors) : ACTORS_DEF;
    // pass 105 (lane LOOK): the structures' and barrels' share, the weapons' models' share
    const shares = {
      structures: fe.structures != null && isFinite(Number(fe.structures)) ? Number(fe.structures) : STRUCTURES_DEF,
      items: fe.items != null && isFinite(Number(fe.items)) ? Number(fe.items) : ITEMS_DEF,
    };
    const SHARE_DEF = { structures: STRUCTURES_DEF, items: ITEMS_DEF };
    const canvas = el('canvas', { class: 'stg-swatch', width: 260, height: 92 });
    const live = { color: f.color, strength: f.strength };
    const redraw = () => drawSwatch(canvas, live, actors, StageModel.bossOf(tl, i));
    const writeFilter = (what) => {
      App.apply((d) => {
        StageModel.setField(d, i, 'filter', { color: live.color, strength: live.strength });
        const ee = d.stage_list.filter(U.isObj)[i];
        if (actors !== ACTORS_DEF || fe.actors != null) ee.filter.actors = Math.round(actors * 100) / 100;
        for (const k of ['structures', 'items']) {
          if (shares[k] !== SHARE_DEF[k] || fe[k] != null) ee.filter[k] = Math.round(shares[k] * 100) / 100;
        }
        App.S.sel = { kind: 'stage', i };
      });
      if (what) App.toast(what, { undo: true, ms: 2000 });
    };
    const presetSel = el('select', { class: 'txt', 'data-path': 'stage.preset' }, el('option', { value: '', text: 'a starting look…' }), ...StageModel.FILTER_PRESETS.map((p) => el('option', { value: p.id, text: p.label })));
    presetSel.addEventListener('change', () => {
      const p = StageModel.FILTER_PRESETS.find((q) => q.id === presetSel.value);
      if (!p) return;
      live.color = p.color; live.strength = p.strength;
      writeFilter(`Stage ${i + 1}'s look: ${p.label}`);
    });
    form.appendChild(fieldRow('Start from', 'fills the colour and the strength (then tune them)', presetSel));
    form.appendChild(fieldRow('Colour', 'the tint the world is multiplied by (blue for an evening dim, red for a blood moon)', Forms.swatchInput(f.strength > 0 || fe.color ? f.color : null, (v) => { live.color = v ? v.toLowerCase() : '#000000'; writeFilter(); }, { path: 'stage.filter.color', placeholder: '#000000', own: 'no tint' })));
    const strength = el('input', { type: 'range', min: 0, max: 1, step: 0.05, value: f.strength, 'data-path': 'stage.filter.strength', class: 'stg-range' });
    const sOut = el('span', { class: 'stg-range-out', text: `${Math.round(f.strength * 100)}%` });
    strength.addEventListener('input', () => { live.strength = Number(strength.value); sOut.textContent = `${Math.round(live.strength * 100)}%`; redraw(); });
    strength.addEventListener('change', () => writeFilter());
    form.appendChild(fieldRow('Strength', '0 = no tint, 1 = the world fully the colour (keep it low: the creatures, gems and red rings must still read)', el('span', { class: 'stg-range-box' }, strength, sOut)));
    const act = el('input', { type: 'range', min: 0, max: 1, step: 0.05, value: actors, 'data-path': 'stage.filter.actors', class: 'stg-range' });
    const aOut = el('span', { class: 'stg-range-out', text: `${Math.round(actors * 100)}%` });
    act.addEventListener('input', () => { actors = Number(act.value); aOut.textContent = `${Math.round(actors * 100)}%`; redraw(); });
    act.addEventListener('change', () => writeFilter());
    form.appendChild(fieldRow('On creatures', 'how much of the tint the creatures and the hero take (lane SLOOK\'s `actors`, 35% when unset): lower keeps them brighter than the world', el('span', { class: 'stg-range-box' }, act, aOut)));
    // pass 105 (lane LOOK): the structures and barrels, the weapons' 3D models (the shots, the creatures' shots and the
    // chests are never tinted)
    const shareRow = (k, label, help) => {
      const r = el('input', { type: 'range', min: 0, max: 1, step: 0.05, value: shares[k], 'data-path': `stage.filter.${k}`, class: 'stg-range' });
      const o = el('span', { class: 'stg-range-out', text: `${Math.round(shares[k] * 100)}%` });
      r.addEventListener('input', () => { shares[k] = Number(r.value); o.textContent = `${Math.round(shares[k] * 100)}%`; });
      r.addEventListener('change', () => writeFilter());
      form.appendChild(fieldRow(label, help, el('span', { class: 'stg-range-box' }, r, o)));
    };
    shareRow('structures', 'On structures', 'how much of the tint the structures, the portal and the barrels take (`structures`, 30% when unset): lower keeps them brighter than the ground');
    shareRow('items', 'On weapons\' models', 'how much of the tint the weapons\' own 3D models take: held guns, companions, orbiters, mines, the turret (`items`, 0% when unset: untinted). The shots, the creatures\' shots and the chests are never tinted');
    form.appendChild(el('div', { class: 'frow' }, el('div', { class: 'flabel', text: 'Preview' }), el('div', { class: 'fctl' }, canvas, el('div', { class: 'muted small', text: 'the map\'s sand, rock and wall colours and the boss: daylight above, this stage below (a red ring stays untinted). The game\'s pictures: lane SLOOK\'s stage_shots.gd.' }))));
    form.appendChild(fieldRow('Hell ground', 'the red hell ground and walls of today\'s stage 3 (RedCanyon.set_hell)', Forms.boolInput ? Forms.boolInput({ key: 'stage.hell' }, !!e.hell, (v) => set('hell', !!v)) : el('input', { type: 'checkbox', checked: !!e.hell, onchange: (ev) => set('hell', ev.target.checked) })));
    // what lies in it
    form.appendChild(el('div', { class: 'fsection' }, el('h3', { text: 'In its window' })));
    const rows = (tl.roster || []).filter((r) => { const t0 = Number(r.t) || 0; const t1 = r.until == null || r.until === '' ? Infinity : Number(r.until); return t0 < w.end && t1 > w.start; });
    const own = rows.filter((r) => (Number(r.t) || 0) >= w.start);
    const evs = (tl.events || []).filter((ev) => { const t = Number(ev.t) || 0; return (t > w.start || (t === w.start && (i === 0 || ev.type !== 'boss'))) && t <= w.end; });
    const pt = (tl.path_times || [])[Math.min(i, Math.max(0, (tl.path_times || []).length - 1))] || [];
    form.appendChild(el('div', { class: 'facts' },
      el('div', { text: `${rows.length} spawn rows open in it (${own.length} start in it, ${rows.length - own.length} come from earlier)` }),
      el('div', { text: `${evs.filter((ev) => ev.type === 'boss').length} boss · ${evs.filter((ev) => ev.type === 'elite_boss').length} Elites · ${pt.length} mutation offers (seconds into the stage: ${pt.join(', ') || 'none'})` }),
      el('div', { text: `at its start → its last second: cap ${App.capAt(w.start)} → ${App.capAt(w.end - 1)} · HP × ${fmtN(App.hpTimeMult(w.start), 2)} → ${fmtN(App.hpTimeMult(w.end - 1), 2)} · ATK × ${fmtN(App.dmgTimeMult(w.start), 2)} → ${fmtN(App.dmgTimeMult(w.end - 1), 2)}` })));
    container.appendChild(form);
    redraw();
  }

  return { renderStrip, card, open, addStage, deleteStage, lengthConfirm, mixHex, multiplied };
})();
