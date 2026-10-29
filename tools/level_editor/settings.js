// The Settings tab (pass 53, pass 54): every scalar of the timeline in a form with its one-line help, the arrays as small
// lists, then the pickups, specials, structures and portal wave blocks. Keys the editor does not know are shown read-only
// and ride along unchanged. Pass 54: the spawn sides as one compass block, the HP x / ATK x curves with their mode switch,
// creature_damage_mult beside creature_hp_mult, hp_growth / hp_power marked legacy.
'use strict';

const Settings = (() => {
  const { el, clear, fmtT } = U;

  const KNOWN = new Set(['roster', 'waves', 'events', 'pickups', 'specials', 'structures', 'portal_wave', 'cap_curve', 'path_times']);
  for (const d of FIELDS.SCALARS) KNOWN.add(d.key.split('.')[0]);

  function render(container) {
    Forms.closePop();
    const active = container.contains(document.activeElement) ? document.activeElement.dataset.path : null;
    const scroll = container.scrollTop;
    clear(container);
    const tl = App.tl();
    const page = el('div', { class: 'settings' });
    page.appendChild(el('p', { class: 'lead', text: 'The numbers behind the lanes. Every change is undoable (Ctrl+Z) and goes to the file with Save. Hover a label, or press its "?", for what the number does.' }));
    const grid = el('div', { class: 'settings-grid' });
    for (const group of FIELDS.SCALAR_GROUPS) {
      const card = el('section', { class: 'card' + (group === 'Scaling' ? ' tall' : '') }, el('h2', { text: group }));
      const blocks = new Set();
      for (const def of FIELDS.SCALARS.filter((d) => d.group === group)) {
        if (def.block) {
          // a block of several keys drawn as one control (the spawn sides' compass)
          if (blocks.has(def.block)) continue;
          blocks.add(def.block);
          if (def.block === 'spawn_sides') card.appendChild(el('div', { class: 'block-row' }, el('h3', { class: 'block-title', text: 'Spawn sides' }), Forms.spawnSidesBlock(tl)));
          // pass 82 (lane XP): the XP card's growth type, its numbers, XP needed × and the two charts (xp_card.js)
          else if (def.block === 'xp_curve' && typeof XpCard !== 'undefined') { card.classList.add('xpc-card'); card.appendChild(XpCard.block(tl)); }
          // pass 112 (lane BARREL): under the respawn rows, about how many come back a stage, then what each barrel kind holds
          else if (def.block === 'barrel_contents' && typeof BarrelCard !== 'undefined') { card.classList.add('tall'); card.appendChild(el('p', { class: 'muted small barrel-summary', text: BarrelCard.summary(tl) })); card.appendChild(BarrelCard.block(tl)); }
          continue;
        }
        // pass 83 (lane SCALE): a row that only counts in another mode stays out of sight (the pegged Boss HP numbers)
        if (typeof def.showIf === 'function' && !def.showIf(tl)) continue;
        if (def.type === 'points') { card.appendChild(Forms.row(def, Forms.pointsBlock(tl))); continue; }
        if (def.type === 'path_times') { card.appendChild(Forms.row(def, Forms.pathTimesBlock(tl))); continue; }
        if (def.type === 'curve') { card.appendChild(Forms.row(def, Forms.curveBlock(tl, def.key), { cls: 'wide-ctl' })); continue; }
        // pass 79 (lane WORLD): a colour of the map's sides shows the game's default faded while its box is empty
        const swatch = def.type === 'swatch' ? { placeholder: def.def, own: 'the game\'s' } : {};
        card.appendChild(Forms.fieldRow(def, tl, Object.assign({ labels: def.type === 'list' ? (i) => `stage ${i + 1}` : undefined }, swatch)));
        // pass 82 (lane SAND): the chosen sand as the phone shows it (sand_previews.png: one 300 px shot a sand, in the
        // order of the row's options; `python tools/gen_sand.py --previews <dir>` from game/tools/_p82_SAND_shots.gd's shots)
        if (def.key === 'sand') {
          const k = Math.max(0, def.options.findIndex((o) => o.v === (tl.sand || def.def)));
          card.appendChild(el('figure', { class: 'sand-preview', style: 'margin:4px 0 10px' },
            el('div', { role: 'img', title: def.options[k].label, style: `width:200px;height:200px;border-radius:6px;background:url(/sand_previews.png) ${def.options.length > 1 ? (k * 100) / (def.options.length - 1) : 0}% 0 / ${def.options.length * 100}% 100% no-repeat` }),
            el('figcaption', { class: 'muted small', text: `${def.options[k].label}, in the game at phone size: the hero on open sand` })));
        }
      }
      // pass 87 (lane STOOLS): each stage's own window (stage_list), set on its tab on the Timeline
      if (group === 'Stages') card.appendChild(el('p', { class: 'muted small', text: `${App.stageList().map((w) => `Stage ${w.i + 1}${w.name !== `Stage ${w.i + 1}` ? ' (' + w.name + ')' : ''} ${fmtT(w.start)}–${fmtT(w.end)}`).join(', ')}. ${Model.hasStageList(App.tl()) ? 'Each stage\'s name, length, boss, words and colour: its tab on the Timeline (+ Stage adds one).' : 'No stage list yet: the stages are Stage length × Stages; editing a stage on its Timeline tab writes a stage list.'} Every stage is its own run since pass 87; the run clock stands still through its boss fight, the portal's countdown and Endless.` }));
      // pass 113 (lane TWISTER): under the dust devils' rows, how many come a stage, when, how long, how big
      if (group === 'Dust devils' && typeof DustDevilCard !== 'undefined') { card.classList.add('tall'); card.appendChild(DustDevilCard.block(tl)); }
      if (group === 'Endless') card.appendChild(el('p', { class: 'muted small', text: 'Pass 87: after every stage\'s boss the portal counts down; then Endless: the first wave at once, then a wave every few seconds, each tougher, until the hero falls. A stage may carry its own `endless` block in its JSON entry (key by key over these). The old endless after the last stage is gone.' }));
      // pass 69 (lane EN)
      if (group === 'Coloured specials') card.appendChild(el('p', { class: 'muted small', text: 'The numbers of a coloured special (the rarer, bigger, tougher, glowing one) wherever a creature\'s own Special block (Enemies tab) leaves a box empty; a creature\'s own number always wins, an empty box here is the game\'s default (the grey number). Every creature names its own size, HP and ATK; none names a glow, so Glow here sets all of them.' }));
      // pass 72 (lane BOSS): the references, the chart and the thinking under the Boss HP card's five rows
      if (group === 'Boss HP' && typeof BossScaling !== 'undefined') card.appendChild(BossScaling.block(tl));
      // pass 83 (lane SCALE): the power formula box, the chart of HP × by power and where the power is charted
      if (group === 'Hero power' && typeof PowerCard !== 'undefined') { card.classList.add('tall'); card.appendChild(PowerCard.block(tl)); }
      if (group === 'Scaling') card.appendChild(el('p', { class: 'muted small', text: 'An ordinary creature spawns with HP = its hp × the stage multiplier × the HP curve at that second × the hero-level factor × creature_hp_mult, and bites for its damage × the stage multiplier × the damage curve × the hero-level factor × creature_damage_mult. The hover cards on the Timeline show both for any second.' }));
      // pass 111 (lane ENEMY): what the far-speed rows add up to, and a warning for a block that reads as a mistake
      if (group === 'Scaling' && typeof Model.farSpeedMult === 'function') {
        const fc = Model.farSpeedCfg(tl);
        const at = [fc.distance, fc.distance + fc.ramp / 2, fc.distance + fc.ramp].map((d) => `${Math.round(d * 10) / 10} m ×${Model.farSpeedMult(tl, d + 1e-6, 'regular').toFixed(2)}`);
        card.appendChild(el('p', { class: 'muted small', text: fc.enabled ? `Far creatures walk faster: ${at.join(', ')} and beyond (a regular creature${fc.bosses ? ' or a boss' : ''}; never an Elite or a special).` : 'Far creatures walk faster: off (every creature walks at its own speed wherever it is).' }));
        for (const w of Model.farSpeedIssues(tl)) card.appendChild(el('p', { class: 'warn-text small', text: w }));
      }
      grid.appendChild(card);
    }
    grid.appendChild(el('section', { class: 'card' }, el('h2', { text: 'Power-up drops' }), el('p', { class: 'muted small', text: 'What kills drop and how often; the harder the creature (its xp_mult) the likelier a drop and the more the hard_bias counts.' }), Forms.pickupsBlock(tl)));
    grid.appendChild(el('section', { class: 'card' }, el('h2', { text: 'Specials' }), el('p', { class: 'muted small', text: 'The Vulture Raider, the Saiga Sniper and the harpooner: not roster creatures but a clock of their own; one comes at a time, drawn evenly from the rows whose stage has come.' }), Forms.specialsBlock(tl)));
    const other = Object.keys(tl).filter((k) => !KNOWN.has(k));
    if (other.length) {
      const o = {};
      for (const k of other) o[k] = tl[k];
      // pass 114 (lane EDITOR): editable as JSON (Apply replaces these keys of timeline_data as typed; a key taken out
      // goes, a new one is added; one undoable edit)
      const card = el('section', { class: 'card' }, el('h2', { text: 'Other keys (kept as they are)' }), el('p', { class: 'muted small', text: 'The editor has no boxes for these; they are written back as they are. Edit them as JSON below if you need to.' }));
      if (typeof JsonEdit !== 'undefined') {
        JsonEdit.inline(card, { summary: 'these keys as JSON', value: o, open: true, path: 'json.other', onApply: (v) => {
          const bad = JsonEdit.mustBeObject(v);
          if (bad) return bad;
          const clash = Object.keys(v).filter((k) => KNOWN.has(k));
          if (clash.length) return `${clash.join(', ')} ${clash.length > 1 ? 'have' : 'has'} its own boxes on this page: change ${clash.length > 1 ? 'them' : 'it'} there`;
          App.apply((t) => { for (const k of other) delete t[k]; Object.assign(t, JSON.parse(JSON.stringify(v))); });
          App.status('The other keys as typed are in the map (Ctrl+Z undoes; Save writes it)', 'good');
          return '';
        } });
      } else card.appendChild(el('pre', { class: 'json', text: JSON.stringify(o, null, 2) }));
      grid.appendChild(card);
    }
    page.appendChild(grid);
    container.appendChild(page);
    container.scrollTop = scroll;
    if (active) { const again = container.querySelector(`[data-path="${CSS.escape(active)}"]`); if (again) again.focus({ preventScroll: true }); }
  }

  return { render };
})();
